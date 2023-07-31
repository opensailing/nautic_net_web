defmodule NauticNetWeb.SailboatPolarsLive do
  use NauticNetWeb, :live_view

  alias Explorer.DataFrame, as: DF

  alias NauticNet.SailboatPolars
  alias NauticNet.SailboatPolars.Interpolation

  alias NauticNetWeb.SailboatPolarsLive.PolarPlot

  alias VegaLite, as: Vl

  defmodule Polars do
    defstruct [
      :id,
      :twa,
      :boat_speed_4,
      :awa_4,
      :boat_speed_6,
      :awa_6,
      :boat_speed_8,
      :awa_8,
      :boat_speed_10,
      :awa_10,
      :boat_speed_12,
      :awa_12,
      :boat_speed_16,
      :awa_16,
      :boat_speed_20,
      :awa_20,
      :boat_speed_24,
      :awa_24
    ]
  end

  defmodule RunBeatPolars do
    defstruct [
      :id,
      :tws,
      :beat_awa,
      :beat_twa,
      :beat_aws,
      :beat_boat_speed,
      :run_awa,
      :run_twa,
      :run_aws,
      :run_boat_speed
    ]
  end

  def mount(_, _, socket) do
    socket = load(socket, :sailboat_polars)

    {:ok, socket}
  end

  def handle_event("plot", %{"polar_plot" => %{"desired_angles" => desired_angles}}, socket) do
    desired_angles = if desired_angles == "", do: nil, else: desired_angles

    cond do
      desired_angles == socket.assigns.desired_angles ->
        {:noreply, socket}

      is_nil(desired_angles) ->
        {:noreply,
         socket
         |> assign(:desired_angles, desired_angles)
         |> push_event("update_polar_plot", %{
           json_spec: plot_json(socket.assigns.interpolation_by_tws, nil)
         })}

      true ->
        angles_of_interest =
          desired_angles
          |> String.split(",", trim: true)
          |> Enum.map(fn val ->
            {v, ""} = val |> String.trim() |> Float.parse()
            v
          end)

        {:noreply,
         socket
         |> assign(:desired_angles, desired_angles)
         |> push_event("update_polar_plot", %{
           json_spec: plot_json(socket.assigns.interpolation_by_tws, angles_of_interest)
         })}
    end
  end

  defp load(socket, :sailboat_polars) do
    {polars_df, run_beat_df} =
      SailboatPolars.load(Path.join(:code.priv_dir(:nautic_net), "sample_sailboat_csv.csv"))

    interpolation_by_tws = SailboatPolars.polar_interpolation(polars_df, run_beat_df)

    socket
    |> assign(
      sailboat_polars: polars_df_to_params(polars_df),
      run_beat_polars: run_beat_polars_df_to_params(run_beat_df),
      interpolation_by_tws: interpolation_by_tws,
      desired_angles: nil
    )
    |> then(
      &push_event(&1, "update_polar_plot", %{json_spec: plot_json(interpolation_by_tws, nil)})
    )
  end

  defp polars_df_to_params(df) do
    df
    |> DF.to_rows()
    |> Enum.with_index(fn row, idx ->
      row
      |> Enum.reject(fn {k, _} -> String.starts_with?(k, "aws_") end)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> then(&struct!(Polars, [{:id, idx} | &1]))
    end)
  end

  defp run_beat_polars_df_to_params(df) do
    df
    |> DF.to_rows()
    |> Enum.with_index(fn row, idx ->
      row
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> then(&struct!(RunBeatPolars, [{:id, idx} | &1]))
    end)
  end

  attr(:speed, :any, default: nil)
  attr(:angle, :any, default: nil)
  slot(:inner_block, required: false)

  defp render_speed_twa(assigns) do
    ~H"""
    <p><.float2 value={@speed} /> kts</p>
    <p><.float2 value={@angle} />°</p>
    """
  end

  attr(:value, :any, default: nil)
  slot(:inner_block, required: false)

  defp float2(assigns) do
    ~H"""
    <span><%= :erlang.float_to_binary(@value, decimals: 2) %></span>
    """
  end

  defp plot_json(interpolation_by_tws, angles_of_interest) do
    radius_marks = Enum.to_list(4..16//2)

    vl_grid =
      PolarPlot.plot_grid(
        opacity: 0.5,
        stroke_color: "white",
        stroke_opacity: 0.5,
        angle_marks: Enum.to_list(0..180//15),
        radius_marks: radius_marks,
        height: 600,
        width: 600
      )

    data_inputs =
      interpolation_by_tws
      |> Enum.flat_map(fn {tws, {model, given_theta, beat_theta, run_theta}} ->
        {start, stop} = Enum.min_max([beat_theta, run_theta | given_theta])
        line_angles = Nx.linspace(start, stop, n: 100)

        angles_of_interest =
          if angles_of_interest do
            Nx.tensor(angles_of_interest)
          else
            Nx.tensor(given_theta)
          end

        line_speeds = Interpolation.predict(model, line_angles) |> Nx.to_list()
        line_angles = Nx.to_list(line_angles)

        speeds = Interpolation.predict(model, angles_of_interest) |> Nx.to_list()
        angles = Nx.to_list(angles_of_interest)

        [
          {line_speeds, line_angles, :line, grouping: tws, point: false},
          {speeds, angles, :point, grouping: tws, tooltip: [content: "data"]}
        ]
      end)

    vl_grid
    |> PolarPlot.plot_data(data_inputs, legend_name: "TWS (kts)", radius_marks: radius_marks)
    |> Vl.Export.to_json()
  end
end
