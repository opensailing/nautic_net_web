defmodule NauticNetWeb.SailboatPolarsLive do
  use NauticNetWeb, :live_view

  alias Explorer.DataFrame, as: DF

  alias NauticNet.SailboatPolars
  alias NauticNet.SailboatPolars.Interpolation

  alias NauticNetWeb.SailboatPolarsLive.PolarPlot

  alias VegaLite, as: Vl

  @deg2rad :math.pi() / 180

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
    {polars_df, run_beat_df} =
      SailboatPolars.load(Path.join(:code.priv_dir(:nautic_net), "sample_sailboat_csv.csv"))

    sku = "h-2-2023-11133-7929-0-579"

    socket =
      socket
      |> assign(
        csv_changeset: csv_changeset(%{}, []),
        rendered_csv: "",
        export_csv: %{},
        sail_kind: "spin",
        desired_angles: Enum.to_list(20..180//10),
        sku: sku,
        plot_title: "Boat Speed (kts) [#{sku} - Spinnaker]"
      )
      |> load(polars_df, run_beat_df)

    {:ok, socket}
  end

  defp csv_changeset(params, required_fields \\ [:sku, :sail_kind]) do
    {%{}, %{sku: :string, sail_kind: :string}}
    |> Ecto.Changeset.cast(params, [:sku, :sail_kind])
    |> Ecto.Changeset.validate_required(required_fields)
    |> Ecto.Changeset.validate_inclusion(:sail_kind, ~w(spin nonspin))
  end

  def handle_event("validate_process_csv", form_data, socket) do
    changeset =
      form_data
      |> csv_changeset()
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket,
       sku: form_data["sku"],
       sail_kind: form_data["sail_kind"],
       csv_changeset: changeset
     )}
  end

  def handle_event(
        "process_csv",
        form_data,
        socket
      ) do
    case csv_changeset(form_data) |> Ecto.Changeset.apply_action(:validate) do
      {:ok, form_data} ->
        {polars_df, run_beat_df} =
          SailboatPolars.load_from_url(form_data.sku, form_data.sail_kind)

        sail = if form_data.sail_kind == "spin", do: "Spinnaker", else: "Non-Spinnaker"

        socket =
          socket
          |> assign(
            sku: form_data.sku,
            sail_kind: form_data.sail_kind,
            plot_title: "Boat Speed (kts) [#{form_data.sku} - #{sail}]"
          )
          |> load(polars_df, run_beat_df)

        # do something
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, csv_changeset: changeset)}
    end
  end

  def handle_event("plot", %{"polar_plot" => %{"desired_angles" => desired_angles}}, socket) do
    desired_angles =
      if desired_angles == "", do: socket.assigns.desired_angles, else: desired_angles

    cond do
      desired_angles == socket.assigns.desired_angles ->
        {:noreply, socket}

      is_nil(desired_angles) ->
        {:noreply,
         socket
         |> assign(:desired_angles, desired_angles)
         |> push_event("update_polar_plot", %{
           json_spec:
             plot_json(socket.assigns.plot_title, socket.assigns.interpolation_by_tws, nil)
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
           json_spec:
             plot_json(
               socket.assigns.plot_title,
               socket.assigns.interpolation_by_tws,
               angles_of_interest
             )
         })}
    end
  end

  def handle_event(
        "export_csv",
        %{"export_csv" => params},
        socket
      ) do
    %{"additional_tws" => additional_tws} = params
    desired_angles = socket.assigns.desired_angles
    desired_angles_t = Nx.tensor(desired_angles)

    additional_tws =
      case additional_tws do
        "" ->
          [2, 14, 18]

        tws_str ->
          tws_str
          |> String.split(",", trim: true)
          |> Enum.map(&(&1 |> String.trim() |> String.to_integer()))
      end

    models_by_tws =
      Map.new(socket.assigns.interpolation_by_tws, fn {tws, {model, _, _, _}} -> {tws, model} end)

    data =
      for {tws, model} <- models_by_tws, into: %{} do
        speeds = Interpolation.predict(model, desired_angles_t) |> Nx.to_list()

        {tws, speeds}
      end

    # TO-DO: remove hardcoded TWSs in favor of input
    tws = Enum.sort(Enum.uniq(Map.keys(data) ++ additional_tws))

    df_cols =
      data
      |> Map.put("twa", desired_angles)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> DF.new()
      |> DF.to_columns()

    csv_header =
      ["TWS" | Enum.map(desired_angles, &(&1 |> round() |> to_string() |> Kernel.<>("°")))]
      |> Enum.join(",")

    csv_body_rows_by_tws = csv_body_rows_by_tws(tws, models_by_tws, df_cols, desired_angles_t)

    csv_header = csv_header <> ",Upwind VMG,Upwind Angle,Downwind VMG,Downwind Angle"

    opt_data_by_tws = opt_data_by_tws(socket.assigns.run_beat_polars)

    [first_tws | _] = existing_tws = Map.keys(opt_data_by_tws) |> Enum.sort()

    tws_intervals = Enum.zip_with(existing_tws, tl(existing_tws), &(&1..&2))

    opt_data_by_tws =
      Enum.reduce(tws, opt_data_by_tws, fn tws, data ->
        {tws, values} =
          case Map.get(data, tws) do
            nil when tws < first_tws ->
              # between 0 and first data point
              t = tws / first_tws
              interpolated = Enum.map(data[first_tws], &lerp(0, &1, t))
              {tws, interpolated}

            nil ->
              start..stop = Enum.find(tws_intervals, &(tws in &1))

              t = (tws - start) / (stop - start)

              start_data = opt_data_by_tws[start]
              stop_data = opt_data_by_tws[stop]

              interpolated = Enum.zip_with(start_data, stop_data, &lerp(&1, &2, t))

              {tws, interpolated}

            values ->
              {tws, values}
          end

        Map.put(data, tws, Enum.map_join(values, ",", &float2str/1))
      end)

    csv_body =
      Enum.map_join(csv_body_rows_by_tws, "\n", fn {tws, row} ->
        row <> "," <> (opt_data_by_tws[tws] || ",,,")
      end)

    csv = String.trim(csv_header <> "\n" <> csv_body)

    {:noreply, assign(socket, rendered_csv: csv, export_csv: params)}
  end

  defp load(socket, polars_df, run_beat_df) do
    interpolation_by_tws = SailboatPolars.polar_interpolation(polars_df, run_beat_df)

    socket
    |> assign(
      sailboat_polars: polars_df_to_params(polars_df),
      run_beat_polars: run_beat_polars_df_to_params(run_beat_df),
      interpolation_by_tws: interpolation_by_tws
    )
    |> then(
      &push_event(&1, "update_polar_plot", %{
        json_spec:
          plot_json(
            socket.assigns.plot_title,
            interpolation_by_tws,
            socket.assigns.desired_angles
          )
      })
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
    <span><%= float2str(@value) %></span>
    """
  end

  defp float2str(i, precision \\ 2)

  defp float2str(i, precision) when is_integer(i) do
    float2str(i * 1.0, precision)
  end

  defp float2str(f, precision) do
    :erlang.float_to_binary(f, decimals: precision)
  end

  defp plot_json(title, interpolation_by_tws, angles_of_interest) do
    radius_marks = Enum.to_list(4..14//2)

    vl_grid =
      PolarPlot.plot_grid(
        title: title,
        opacity: 0.25,
        color: "lightgrey",
        stroke_color: "black",
        stroke_opacity: 0.5,
        angle_marks: Enum.to_list(0..180//15),
        radius_marks: radius_marks,
        height: 1000,
        width: 1000
      )

    data_inputs =
      interpolation_by_tws
      |> Enum.flat_map(fn {tws, {model, given_theta, beat_theta, run_theta}} ->
        {min_given_theta, max_given_theta} = Enum.min_max([beat_theta, run_theta | given_theta])

        angles_of_interest_l = Enum.sort(angles_of_interest || given_theta)

        angles_of_interest = Nx.tensor(angles_of_interest_l)

        {start, stop} = Enum.min_max(angles_of_interest_l)
        line_angles = Nx.linspace(start, stop, n: 500)

        line_speeds = Interpolation.predict(model, line_angles) |> Nx.to_list()
        line_angles = Nx.to_list(line_angles)

        speeds = Interpolation.predict(model, angles_of_interest) |> Nx.to_list()

        {low_a, low_s, mid_a, mid_s, high_a, high_s} =
          split_lines(line_speeds, line_angles, min_given_theta, max_given_theta)

        build_line_segment = fn r, theta, stroke_dash ->
          {%{
             r: r,
             theta: theta,
             "TWS (kts)": List.duplicate(tws, length(r))
           }, :line, stroke_width: 3, point: false, stroke_dash: stroke_dash}
        end

        [
          build_line_segment.(low_s, low_a, [4, 4]),
          build_line_segment.(mid_s, mid_a, [1, 0]),
          build_line_segment.(high_s, high_a, [4, 4]),
          {%{
             r: speeds,
             theta: angles_of_interest_l,
             "TWS (kts)": List.duplicate(tws, length(line_speeds))
           }, :point,
           size: 8,
           stroke_width: 8,
           shape: %{
             expr:
               "(datum.theta < #{min_given_theta} || datum.theta > #{max_given_theta}) ? 'triangle' : 'circle'"
           }}
        ]
      end)

    vl_grid
    |> PolarPlot.plot_data(data_inputs, legend_name: "TWS (kts)", radius_marks: radius_marks)
    |> Vl.Export.to_json()
  end

  defp lerp(start, stop, t), do: start + (stop - start) * t

  defp split_lines(line_speeds, line_angles, min_given_theta, max_given_theta) do
    Enum.zip_reduce(line_speeds, line_angles, {[], [], [], [], [], []}, fn s,
                                                                           a,
                                                                           {low_a, low_s, mid_a,
                                                                            mid_s, high_a,
                                                                            high_s} ->
      cond do
        a < min_given_theta ->
          {[a | low_a], [s | low_s], mid_a, mid_s, high_a, high_s}

        a > max_given_theta ->
          {low_a, low_s, mid_a, mid_s, [a | high_a], [s | high_s]}

        true ->
          {low_a, low_s, [a | mid_a], [s | mid_s], high_a, high_s}
      end
    end)
  end

  defp opt_data_by_tws(run_beat_polars) do
    Map.new(run_beat_polars, fn %{
                                  tws: tws,
                                  beat_boat_speed: beat_boat_speed,
                                  beat_twa: beat_twa,
                                  run_boat_speed: run_boat_speed,
                                  run_twa: run_twa
                                } ->
      values = [
        beat_boat_speed * :math.cos(@deg2rad * beat_twa),
        beat_twa,
        abs(run_boat_speed * :math.cos(@deg2rad * run_twa)),
        run_twa
      ]

      {round(tws), values}
    end)
  end

  defp csv_body_rows_by_tws(tws, models_by_tws, df_cols, desired_angles_t) do
    Enum.map(tws, fn k ->
      values =
        case df_cols[to_string(k)] do
          nil ->
            models_by_tws |> Interpolation.predict_new_tws(k, desired_angles_t) |> Nx.to_list()

          val ->
            val
        end

      {k, to_string(k) <> "," <> Enum.map_join(values, ",", &float2str/1)}
    end)
  end
end
