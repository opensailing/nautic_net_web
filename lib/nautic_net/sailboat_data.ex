defmodule NauticNet.SailboatData do
  @moduledoc """
  Parses a CSV file into an Explorer dataframe.

  Also provides functionality for interpolating the data.
  """

  require Explorer.DataFrame
  alias Explorer.DataFrame, as: DF
  alias Explorer.Series, as: S

  @special_col_names ["True Wind Speed", "Opt Beat Angle", "Beat VMG", "Opt Run Angle", "Run VMG"]

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

    # note: these are vmgs. We need to check if the other speeds are too.
    # to convert from vmg to tws (boat speed), just divide by cos(twa)
    run_vmg = S.divide(@miles_per_sec_to_kts, optimal_data["Run VMG"])

    {run_aws_kts, run_awa} =
      convert_series(
        run_vmg,
        tws_series,
        optimal_data["Opt Run Angle"]
      )

    beat_vmg = S.divide(@miles_per_sec_to_kts, optimal_data["Beat VMG"])

    {beat_aws_kts, beat_awa} =
      convert_series(
        beat_vmg,
        tws_series,
        optimal_data["Opt Beat Angle"]
      )

    optimal_angles_df =
      %{
        "Beat AWA" => beat_awa,
        "Beat AWS" => beat_aws_kts,
        "Beat VMG" => beat_vmg,
        "Run AWA" => run_awa,
        "Run AWS" => run_aws_kts,
        "Run VMG" => run_vmg,
        "TWS" => tws_series
      }
      |> DF.new()

    {df, optimal_angles_df}
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

        [
          {String.trim_trailing(col, " kts"), result},
          {:"#{String.trim_trailing(col, " kts")}_awa", awa}
        ]
      end)
    end)
    |> DF.discard(tws_cols)
  end

  defp convert_series(v_boat, v_wind, twa) do
    IO.inspect({v_boat, v_wind, twa})
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
