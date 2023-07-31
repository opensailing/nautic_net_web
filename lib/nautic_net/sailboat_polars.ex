defmodule NauticNet.SailboatPolars do
  @moduledoc """
  Parses a CSV file into an Explorer dataframe.

  Also provides functionality for interpolating the data.
  """

  alias Explorer.DataFrame, as: DF
  alias Explorer.Series, as: S

  alias NauticNet.SailboatPolars.Interpolation

  require Explorer.DataFrame

  @miles_per_sec_to_kts 3128.31

  @doc """
  Loads the CSV file given by `filename`.

  The columns `True Wind Speed`, `Opt Beat Angle`,
  `Beat VMG`, `Opt Run Angle` and `Run VMG` are treated especially.

  All other column names are expected to be a angles in degrees.
  """
  def load(filename) do
    df = DF.from_csv!(filename) |> DF.rename("True Wind Speed": "row_names")

    split_index =
      df["row_names"] |> S.to_list() |> Enum.find_index(&String.starts_with?(&1, "--"))

    optimal_angles_df = DF.tail(df, DF.n_rows(df) - split_index - 1)

    df = DF.head(df, split_index)

    twa =
      df["row_names"]
      |> S.to_list()
      |> Enum.map(fn angle ->
        {angle, _} = Float.parse(angle)
        angle
      end)
      |> S.from_list()

    df = df |> DF.put(:twa, twa) |> DF.discard(["row_names"]) |> calculate_speed_in_kts()

    tws_cols = DF.names(optimal_angles_df) -- ["row_names"]
    tws_series = tws_cols |> Enum.map(&(&1 |> Float.parse() |> elem(0))) |> S.from_list()

    optimal_data =
      optimal_angles_df
      |> Explorer.DataFrame.to_rows()
      |> Map.new(fn row ->
        {row["row_names"], Enum.map(tws_cols, &row[&1]) |> Explorer.Series.from_list()}
      end)

    run_twa = optimal_data["Opt Run Angle"]

    run_speed_kts =
      @miles_per_sec_to_kts
      |> S.divide(optimal_data["Run VMG"])
      |> S.divide(
        S.cos(
          S.subtract(
            :math.pi(),
            S.multiply(run_twa, :math.pi() / 180)
          )
        )
      )

    {run_aws_kts, run_awa} =
      convert_series(
        run_speed_kts,
        tws_series,
        run_twa
      )

    beat_twa = optimal_data["Opt Beat Angle"]

    beat_speed_kts =
      @miles_per_sec_to_kts
      |> S.divide(optimal_data["Beat VMG"])
      |> S.divide(S.cos(S.multiply(beat_twa, :math.pi() / 180)))

    {beat_aws_kts, beat_awa} =
      convert_series(
        beat_speed_kts,
        tws_series,
        beat_twa
      )

    optimal_angles_df =
      DF.new(%{
        "beat_awa" => beat_awa,
        "beat_twa" => beat_twa,
        "beat_aws" => beat_aws_kts,
        "beat_boat_speed" => beat_speed_kts,
        "run_awa" => run_awa,
        "run_twa" => run_twa,
        "run_aws" => run_aws_kts,
        "run_boat_speed" => run_speed_kts,
        "tws" => tws_series
      })

    {df, optimal_angles_df}
  end

  @doc """
  Build polar interpolation from the dataframes loaded in `load/1`
  """
  def polar_interpolation(polar_df, run_beat_df, opts \\ []) do
    opts = Keyword.validate!(opts, force_zero: false, interpolate_run_and_beat: false)

    run_beat_df
    |> DF.to_rows()
    |> Enum.map(fn row ->
      tws = trunc(row["tws"])
      beat_theta = row["beat_twa"]
      beat_boat_speed = row["beat_boat_speed"]
      run_theta = row["run_twa"]
      run_boat_speed = row["run_boat_speed"]

      run_beat_theta = [beat_theta, run_theta]
      run_beat_r = [beat_boat_speed, run_boat_speed]

      {theta, r} =
        if opts[:interpolate_run_and_beat] do
          {run_beat_theta, run_beat_r}
        else
          {[], []}
        end

      {theta, r} =
        polar_df
        |> DF.select(["twa", "awa_#{tws}", "boat_speed_#{tws}"])
        |> DF.rename("awa_#{tws}": "awa", "boat_speed_#{tws}": "boat_speed")
        |> DF.to_rows()
        |> Enum.reduce({theta, r}, fn row, {theta, r} ->
          {[row["twa"] | theta], [row["boat_speed"] | r]}
        end)

      given_theta = theta

      {r, theta} =
        if opts[:force_zero] do
          theta = Nx.tensor([0 | theta])
          r = Nx.tensor([0 | r])
          {r, theta}
        else
          theta = Nx.tensor(theta)
          r = Nx.tensor(r)
          {r, theta}
        end

      model = Interpolation.fit(theta, r)

      {tws, {model, given_theta, beat_theta, run_theta}}
    end)
  end

  defp calculate_speed_in_kts(df) do
    tws_cols = DF.names(df) -- ["twa"]
    tws_df = tws_cols |> Map.new(&{&1, [&1 |> Float.parse() |> elem(0)]}) |> DF.new()

    df =
      Enum.reduce(tws_cols, df, fn col, df ->
        DF.mutate(df, [{^col, ^@miles_per_sec_to_kts / col(^col)}])
      end)

    tws_cols
    |> Enum.reduce(df, fn col, df ->
      DF.mutate_with(df, fn df ->
        {result, awa} = convert_series(df[col], tws_df[col], df["twa"])

        col_name = String.trim_trailing(col, " kts")

        [
          {:"boat_speed_#{col_name}", result},
          {:"awa_#{col_name}", awa}
        ]
      end)
    end)
    |> DF.discard(tws_cols)
  end

  defp convert_series(v_boat, v_wind, twa) do
    v_boat_sq = S.pow(v_boat, 2.0)
    v_wind_sq = S.pow(v_wind, 2.0)

    cos = twa |> S.multiply(:math.pi() / 180) |> S.cos()
    cos_component = 2 |> S.multiply(v_wind) |> S.multiply(v_boat) |> S.multiply(cos)

    result =
      v_boat_sq
      |> S.add(v_wind_sq)
      |> S.add(cos_component)
      |> S.pow(0.5)

    awa =
      v_wind
      |> S.multiply(cos)
      |> S.add(v_boat)
      |> S.divide(result)
      |> S.acos()
      |> S.multiply(180 / :math.pi())

    {result, awa}
  end
end
