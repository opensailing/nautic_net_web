defmodule NauticNetWeb.MapLive do
  use NauticNetWeb, :live_view

  alias Phoenix.PubSub
  alias NauticNet.Data.Sample
  alias NauticNet.Coordinates
  alias NauticNet.Playback
  alias NauticNet.Playback.DataSource

  require Logger

  @hingham_bounding_box %{
    "min_lat" => 42.1666,
    "max_lat" => 42.4093,
    "min_lon" => -71.0473,
    "max_lon" => -70.8557
  }

  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(NauticNet.PubSub, "leaflet")

    socket =
      socket
      # UI toggles
      |> assign(:tracks_visible?, true)
      |> assign(:water_visible?, false)
      |> assign(:is_live?, false)
      |> assign(:data_sources_modal_visible?, false)

      # Water currents
      |> assign(:last_water_event_sent_at, now_ms())
      |> assign(:last_water_event_index, nil)

      # Map
      |> assign(:bounding_box, @hingham_bounding_box)
      |> assign(:zoom_level, 15)

      # Timeline
      |> assign(:timezone, "America/New_York")
      |> assign_dates()

      # Selected boat
      # |> assign_coordinates(Coordinates.get_coordinates("trip-01.csv"))
      |> assign_selected_boat_coordinates()

    {:ok, socket}
  end

  defp assign_selected_boat_coordinates(socket) do
    coordinates =
      Playback.list_coordinates(
        socket.assigns.selected_boat,
        socket.assigns.selected_date,
        socket.assigns.timezone,
        socket.assigns.data_sources
      )

    assign_coordinates(socket, coordinates)
  end

  defp assign_coordinates(socket, [initial_coordinate | _] = coordinates) do
    map_center = Coordinates.get_center(coordinates)

    socket
    |> set_track_coordinates(coordinates)
    |> set_map_view(map_center)
    |> set_marker_coordinate(initial_coordinate)
    |> assign(:current_coordinate, initial_coordinate)
    |> assign(:coordinates, coordinates)
    |> assign(:map_center, map_center)
    |> assign(:min_position, 0)
    |> assign(:max_position, Enum.count(coordinates) - 1)
    |> push_event("update_max", %{id: "range", max: Enum.count(coordinates) - 1})
    |> assign(:current_min_position, 0)
    |> assign(:current_max_position, Enum.count(coordinates) - 1)
    |> assign(:current_position, 0)
  end

  def handle_event(
        "change_bounds",
        %{"bounds" => bounding_box, "zoom_level" => zoom_level},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:bounding_box, bounding_box)
     |> set_position(%{"zoom_level" => zoom_level, "viewport_change" => true})}
  end

  def handle_event("set_position", params, socket) do
    {:noreply, set_position(socket, params)}
  end

  def handle_event("clear", _, socket), do: {:noreply, push_event(socket, "clear_polyline", %{})}

  def handle_event("toggle_track", _, %{assigns: %{tracks_visible?: value}} = socket) do
    {:noreply,
     socket
     |> assign(:tracks_visible?, not value)
     |> push_event("toggle_track", %{value: not value})}
  end

  def handle_event("update_range", %{"min" => min, "max" => max}, socket) do
    {min_value, _} = Integer.parse(min)
    {max_value, _} = Integer.parse(max)

    {:noreply,
     socket
     |> set_marker_position(min_value)
     |> assign(:current_coordinate, Enum.at(socket.assigns.coordinates, min_value))
     |> assign(:current_position, min_value)
     |> assign(:current_min_position, min_value)
     |> assign(:current_max_position, max_value)}
  end

  def handle_event("select_date", %{"date" => date_param}, socket) do
    date = Date.from_iso8601!(date_param)

    {:noreply, select_date(socket, date)}
  end

  def handle_event("select_boat", %{"boat_id" => boat_id}, socket) do
    boat = Enum.find(socket.assigns.boats, &(&1.id == boat_id)) || raise "invalid boat_id"

    {:noreply, select_boat(socket, boat)}
  end

  def handle_event("is_live_changed", %{"is_live" => is_live_param}, socket) do
    is_live? = is_live_param == "true"

    {
      :noreply,
      socket
      |> assign(:is_live?, is_live?)
      # RangeSlider state must be updated via JS hook because it has phx-update="ignore"
      |> push_event("set_enabled", %{id: "range", enabled: not is_live?})
      # TODO: More things
    }
  end

  def handle_event("water_visible_changed", %{"water_visible" => water_visible_param}, socket) do
    socket =
      case water_visible_param do
        "true" ->
          socket
          |> assign(:water_visible?, true)
          |> set_position(%{"viewport_change" => true})

        _false ->
          socket
          |> assign(:water_visible?, false)
          |> push_event("clear_water_markers", %{})
      end

    {:noreply, socket}
  end

  def handle_event("select_data_sources", params, socket) do
    {:noreply, select_sensors(socket, params)}
  end

  def handle_event("show_data_sources_modal", _, socket) do
    {:noreply, assign(socket, :data_sources_modal_visible?, true)}
  end

  def handle_event("data_sources_modal_closed", _, socket) do
    {:noreply, assign(socket, :data_sources_modal_visible?, false)}
  end

  defp set_position(%{assigns: assigns} = socket, params) do
    {throttle, new_position} =
      case params["position"] do
        nil ->
          {false, assigns.current_position}

        pos ->
          {true, String.to_integer(pos)}
      end

    viewport_change? = params["viewport_change"] == true
    zoom_level = params["zoom_level"] || assigns.zoom_level

    new_coordinates = Enum.at(assigns.coordinates, new_position)

    # epoch for fixed dataset is from 59898.0 to 59904.0
    # 10751 is the max value for position

    now = now_ms()
    diff_ms = now - assigns.last_water_event_sent_at

    {time, _new_lat, _new_lon} = new_coordinates
    {t0, _, _} = Enum.at(assigns.coordinates, 0)

    milliseconds_diff = DateTime.diff(time, t0, :millisecond)
    time = NauticNet.NetCDF.epoch() + milliseconds_diff / (24 * :timer.hours(1))

    index = NauticNet.NetCDF.get_geodata_time_index(time)

    {last_water_event_index, last_water_event_sent_at, water_data} =
      if (index != assigns.last_water_event_index or viewport_change?) and
           ((throttle and diff_ms > 33) or not throttle) and assigns.water_visible? do
        %{
          "min_lat" => min_lat,
          "min_lon" => min_lon,
          "max_lat" => max_lat,
          "max_lon" => max_lon
        } = assigns.bounding_box

        data =
          index
          |> NauticNet.NetCDF.get_geodata(min_lat, max_lat, min_lon, max_lon, zoom_level)
          |> Base.encode64()

        {index, now, data}
      else
        {assigns.last_water_event_index, assigns.last_water_event_sent_at, nil}
      end

    data_sources =
      Playback.fill_latest_samples(
        socket.assigns.selected_boat,
        current_datetime(new_coordinates),
        socket.assigns.data_sources
      )

    socket =
      socket
      |> set_marker_position(new_position)
      |> assign(:current_position, new_position)
      |> assign(:current_coordinate, new_coordinates)
      |> assign(:last_water_event_sent_at, last_water_event_sent_at)
      |> assign(:last_water_event_index, last_water_event_index)
      |> assign(:zoom_level, zoom_level)
      |> assign(:data_sources, data_sources)

    if water_data do
      push_event(socket, "add_water_markers", %{water_data: water_data})
    else
      socket
    end
  end

  defp print_coordinate({utc_datetime, latitude, longitude}, timezone) do
    local_datetime =
      utc_datetime
      |> Timex.to_datetime(timezone)
      |> Timex.format!("{h12}:{m}:{s} {am} {Zabbr}")

    "#{local_datetime} [#{Float.round(latitude, 4)}, #{Float.round(longitude, 4)}]"
  end

  defp assign_dates(socket) do
    [first_date | _] = dates = Playback.list_all_dates(socket.assigns.timezone)

    socket
    |> assign(:dates, dates)
    |> select_date(first_date)
  end

  # Set the date, boats, and data sources
  defp select_date(socket, date) do
    [first_boat | _] = boats = Playback.list_active_boats(date, socket.assigns.timezone)

    socket
    |> assign(:selected_date, date)
    |> assign(:boats, boats)
    |> select_boat(first_boat)
  end

  defp select_boat(socket, boat) do
    socket
    |> assign(:selected_boat, boat)
    |> assign(
      :data_sources,
      Playback.list_data_sources(
        boat,
        socket.assigns.selected_date,
        socket.assigns.timezone
      )
    )
    |> assign_selected_boat_coordinates()
  end

  # Update each DataSource's :selected_sensor based on form params
  defp select_sensors(socket, params) do
    data_sources =
      for data_source <- socket.assigns.data_sources do
        next_sensor = Enum.find(data_source.sensors, &(&1.id == params[data_source.id]))
        %{data_source | selected_sensor: next_sensor}
      end

    assign(socket, :data_sources, data_sources)
  end

  defp sensor_count(data_sources) do
    data_sources
    |> Enum.flat_map(fn data_source ->
      Enum.map(data_source.sensors, & &1.id)
    end)
    |> Enum.uniq()
    |> Enum.count()
  end

  # <select> option helpers

  defp boat_options(boats) do
    Enum.map(boats, &{&1.name, &1.id})
  end

  defp date_options(dates) do
    Enum.map(dates, &Date.to_iso8601/1)
  end

  defp sensor_options([]), do: [{"Not Available", ""}]

  defp sensor_options(sensors) do
    [{"Off", ""}] ++ Enum.map(sensors, &{&1.name, &1.id})
  end

  defp current_datetime({utc_datetime, _lat, _lon}), do: utc_datetime

  defp get_latest_sample(data_sources, data_source_id) do
    case Enum.find(data_sources, &(&1.id == data_source_id)) do
      %DataSource{latest_sample: %Sample{} = sample} -> sample
      _ -> nil
    end
  end

  attr(:label, :string, required: true)
  attr(:sample, :map, required: true)
  attr(:field, :atom, required: true, values: [:angle_rad, :depth_m, :speed_m_s])
  attr(:unit, :atom, required: true, values: [:deg, :kn, :ft])

  defp sample_view(assigns) do
    display_value =
      if assigns.sample do
        case assigns.field do
          :angle_rad ->
            assigns.sample.angle
            |> convert(:rad, assigns.unit)
            |> :erlang.float_to_binary(decimals: 0)

          :depth_m ->
            assigns.sample.magnitude
            |> convert(:m, assigns.unit)
            |> :erlang.float_to_binary(decimals: 1)

          :speed_m_s ->
            assigns.sample.magnitude
            |> convert(:m_s, assigns.unit)
            |> :erlang.float_to_binary(decimals: 1)
        end
      else
        "--"
      end

    assigns = assign(assigns, display_value: display_value)

    ~H"""
    <div class="border rounded-lg p-2 flex flex-col">
      <div class="flex justify-between font-semibold text-sm">
        <div><%= @label %></div>
        <div><%= unit(@unit) %></div>
      </div>
      <div class="text-center text-4xl flex-grow flex items-center justify-center">
        <%= @display_value %>
      </div>
    </div>
    """
  end

  defp unit(:deg), do: "°"
  defp unit(:kn), do: "kn"
  defp unit(:ft), do: "ft"

  defp convert(value, :m_s, :m_s), do: value * 1.0
  defp convert(value, :m_s, :kn), do: value * 1.94384

  defp convert(value, :rad, :rad), do: value * 1.0
  defp convert(value, :rad, :deg), do: value * 180 / :math.pi()

  defp convert(value, :m, :m), do: value * 1.0
  defp convert(value, :m, :ft), do: value * 3.28084

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp set_map_view(socket, {latitude, longitude}) do
    push_event(socket, "map_view", %{latitude: latitude, longitude: longitude})
  end

  defp set_marker_coordinate(socket, {_date, latitude, longitude}) do
    push_event(socket, "marker_coordinate", %{latitude: latitude, longitude: longitude})
  end

  defp set_marker_position(socket, position) do
    push_event(socket, "marker_position", %{position: position})
  end

  defp set_track_coordinates(socket, coordinates) do
    dateless_coordinates =
      Enum.map(coordinates, fn {_date, latitude, longitude} -> [latitude, longitude] end)

    push_event(socket, "track_coordinates", %{coordinates: dateless_coordinates})
  end
end
