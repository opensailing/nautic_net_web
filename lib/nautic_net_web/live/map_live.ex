defmodule NauticNetWeb.MapLive do
  use NauticNetWeb, :live_view

  alias Phoenix.PubSub
  alias NauticNet.Animation
  alias NauticNet.Data.Sample
  alias NauticNet.Coordinates
  alias NauticNet.Playback
  alias NauticNet.Playback.DataSource

  require Logger

  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(NauticNet.PubSub, "leaflet")

    {now, us} = DateTime.utc_now() |> DateTime.to_gregorian_seconds()
    now = now + us / 1_000_000

    min_lat = 42.1666
    max_lat = 42.4093
    min_lon = -71.0473
    max_lon = -70.8557

    socket =
      socket
      |> assign(:timezone, "America/New_York")
      |> assign(:animate_time, false)
      |> assign(:show_track, true)
      |> assign(:last_current_event_sent_at, now)
      |> assign(:bounding_box, %{
        "min_lat" => min_lat,
        "min_lon" => min_lon,
        "max_lat" => max_lat,
        "max_lon" => max_lon
      })
      |> assign(:last_current_event_index, nil)
      |> assign(:is_live, false)
      |> assign_dates()
      |> assign(:data_sources_modal_visible?, false)
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

  defp assign_coordinates(socket, [initial_coordinates | _] = coordinates) do
    map_center = Coordinates.get_center(coordinates)

    Animation.set_track_coordinates(coordinates)
    Animation.set_map_view(map_center)
    Animation.set_marker_coordinates(initial_coordinates)

    socket
    |> assign(:current_coordinates, initial_coordinates)
    |> assign(:coordinates, coordinates)
    |> assign(:map_center, map_center)
    |> assign(:min_position, 0)
    |> assign(:max_position, Enum.count(coordinates) - 1)
    |> assign(:current_min_position, 0)
    |> assign(:current_max_position, Enum.count(coordinates) - 1)
    |> assign(:current_position, 0)
  end

  def handle_event(
        "change_bounds",
        %{"bounds" => bounding_box, "zoom_level" => zoom_level},
        socket
      ) do
    handle_event(
      "set_position",
      %{"zoom_level" => zoom_level, "viewport_change" => true},
      assign(socket, :bounding_box, bounding_box)
    )
  end

  def handle_event("set_position", event_data, %{assigns: assigns} = socket) do
    {throttle, new_position} = set_throttle_and_position(event_data, assigns)

    viewport_change = event_data["viewport_change"] == true

    zoom_level = event_data["zoom_level"] || 15

    new_coordinates = Enum.at(assigns.coordinates, new_position)
    Animation.set_marker_position(new_position)

    # epoch for fixed dataset is from 59898.0 to 59904.0
    # 10751 is the max value for position

    {now, us} = DateTime.utc_now() |> DateTime.to_gregorian_seconds()
    now = now + us / 1_000_000
    diff = now - assigns.last_current_event_sent_at

    {time, _new_lat, _new_lon} = new_coordinates
    {t0, _, _} = Enum.at(assigns.coordinates, 0)

    milliseconds_diff = DateTime.diff(time, t0, :millisecond)
    time = NauticNet.NetCDF.epoch() + milliseconds_diff / (24 * :timer.hours(1))

    index = NauticNet.NetCDF.get_geodata_time_index(time)

    {last_current_event_index, last_current_event_sent_at, current_data} =
      if (index != assigns.last_current_event_index or viewport_change) and
           ((throttle and diff > 1 / 30) or not throttle) do
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
        {assigns.last_current_event_index, assigns.last_current_event_sent_at, nil}
      end

    data_sources =
      Playback.fill_latest_samples(
        socket.assigns.selected_boat,
        current_datetime(new_coordinates),
        socket.assigns.data_sources
      )

    socket =
      socket
      |> assign(:current_position, new_position)
      |> assign(:current_coordinates, new_coordinates)
      |> assign(:last_current_event_sent_at, last_current_event_sent_at)
      |> assign(:last_current_event_index, last_current_event_index)
      |> assign(:data_sources, data_sources)

    socket =
      if current_data do
        push_event(socket, "add_current_markers", %{current_data: current_data})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("clear", _, socket), do: {:noreply, push_event(socket, "clear_polyline", %{})}

  def handle_event("toggle_track", _, %{assigns: %{show_track: value}} = socket) do
    {:noreply,
     socket
     |> assign(:show_track, !value)
     |> push_event("toggle_track", %{value: !value})}
  end

  def handle_event("update_range", %{"min" => min, "max" => max}, socket) do
    {min_value, _} = Integer.parse(min)
    {max_value, _} = Integer.parse(max)

    Animation.set_marker_position(min_value)

    {:noreply,
     socket
     |> assign(:current_coordinates, Enum.at(socket.assigns.coordinates, min_value))
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
    is_live = is_live_param == "true"

    {
      :noreply,
      socket
      |> assign(:is_live, is_live)
      # RangeSlider state must be updated via JS hook because it has phx-update="ignore"
      |> push_event("set_enabled", %{id: "range", enabled: not is_live})
      # TODO: More things
    }
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

  def handle_info({"track_coordinates", coordinates}, socket) do
    {:noreply, push_event(socket, "track_coordinates", %{coordinates: coordinates})}
  end

  def handle_info({"marker_position", position}, socket) do
    {:noreply, push_event(socket, "marker_position", %{position: position})}
  end

  def handle_info({event, latitude, longitude}, socket) do
    {:noreply, push_event(socket, event, %{latitude: latitude, longitude: longitude})}
  end

  defp set_throttle_and_position(event_data, assigns) do
    {throttle, new_position} =
      case event_data["position"] do
        nil ->
          {false, assigns.current_position}

        pos ->
          {true, String.to_integer(pos)}
      end
  end

  defp print_coordinates({utc_datetime, latitude, longitude}, timezone) do
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
end
