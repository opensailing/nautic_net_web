defmodule NauticNetWeb.MapLive do
  use NauticNetWeb, :live_view

  alias Phoenix.PubSub
  alias NauticNet.Data.Sample
  alias NauticNet.Coordinates
  alias NauticNet.Playback
  alias NauticNet.Playback.DataSource

  require Logger

  defmodule BoatView do
    defstruct boat: nil, coordinates: [], visible?: true, data_sources: [], track_color: nil
  end

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

      # Boats
      |> assign(:boat_views, [])

      # Map
      |> assign(:bounding_box, @hingham_bounding_box)
      |> assign(:zoom_level, 15)

      # Timeline
      |> assign(:inspect_at, DateTime.utc_now())
      |> assign(:timezone, "America/New_York")
      |> assign_dates_and_boats()

    # Selected boat
    # |> assign_coordinates(Coordinates.get_coordinates("trip-01.csv"))

    {:ok, socket}
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
    range_start_at = parse_unix_datetime(min, socket.assigns.timezone)
    range_end_at = parse_unix_datetime(max, socket.assigns.timezone)

    {:noreply,
     socket
     |> assign(:range_start_at, range_start_at)
     |> assign(:range_end_at, range_end_at)
     |> constrain_inspect_at()
     |> push_map_state()}
  end

  def handle_event("set_boat_visible", %{"boat-id" => boat_id} = params, socket) do
    visible? = params["value"] == "on"

    socket =
      socket
      |> update_boat_view(boat_id, fn boat_view ->
        %{boat_view | visible?: visible?}
      end)
      |> push_event("set_boat_visible", %{boat_id: boat_id, visible: visible?})

    {:noreply, socket}
  end

  def handle_event("select_date", %{"date" => date_param}, socket) do
    date = Date.from_iso8601!(date_param)

    {:noreply, select_date(socket, date)}
  end

  def handle_event("select_boat", %{"boat_id" => boat_id}, socket) do
    {:noreply, select_boat_view(socket, boat_id)}
  end

  def handle_event("is_live_changed", %{"is_live" => is_live_param}, socket) do
    is_live? = is_live_param == "true"

    {
      :noreply,
      socket
      |> assign(:is_live?, is_live?)
      # RangeSlider state must be updated via JS hook because it has phx-update="ignore"
      |> push_event("set_enabled", %{id: "range-slider", enabled: not is_live?})
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

  def handle_event(
        "select_data_sources",
        params,
        %{assigns: %{selected_boat_view: selected_boat_view}} = socket
      ) do
    data_sources =
      for data_source <- selected_boat_view.data_sources do
        next_sensor = Enum.find(data_source.sensors, &(&1.id == params[data_source.id]))
        %{data_source | selected_sensor: next_sensor}
      end

    new_boat_view = %{selected_boat_view | data_sources: data_sources}

    socket = put_boat_view(socket, new_boat_view)

    {:noreply, socket}
  end

  def handle_event("show_data_sources_modal", _, socket) do
    {:noreply, assign(socket, :data_sources_modal_visible?, true)}
  end

  def handle_event("hide_data_sources_modal", _, socket) do
    {:noreply, assign(socket, :data_sources_modal_visible?, false)}
  end

  defp push_boat_views(socket) do
    boat_views =
      Enum.map(socket.assigns.boat_views, fn bv ->
        %{
          "boat_id" => bv.boat.id,
          "track_color" => bv.track_color,
          "coordinates" =>
            Enum.map(bv.coordinates, fn coord ->
              %{
                "time" => DateTime.to_unix(coord.time),
                "lat" => coord.latitude,
                "lng" => coord.longitude,
                "heading_rad" => coord.true_heading
              }
            end)
        }
      end)

    push_event(socket, "boat_views", %{"boat_views" => boat_views})
  end

  defp push_map_state(%{assigns: assigns} = socket) do
    push_event(socket, "map_state", %{
      first_sample_at: DateTime.to_unix(assigns.first_sample_at),
      last_sample_at: DateTime.to_unix(assigns.last_sample_at),
      range_start_at: DateTime.to_unix(assigns.range_start_at),
      range_end_at: DateTime.to_unix(assigns.range_end_at),
      inspect_at: DateTime.to_unix(assigns.inspect_at)
    })
  end

  defp set_position(%{assigns: assigns} = socket, params) do
    # epoch for fixed dataset is from 59898.0 to 59904.0
    # 10751 is the max value for position

    new_inspect_at =
      if pos = params["position"] do
        parse_unix_datetime(pos, assigns.timezone)
      else
        assigns.inspect_at
      end

    socket =
      Enum.reduce(assigns.boat_views, socket, fn boat_view, socket ->
        # TEMP: Do nothing right now
        new_data_sources = boat_view.data_sources

        # TODO: Make sample fetching more efficient
        # Playback.fill_latest_samples(
        #   boat_view.boat,
        #   new_inspect_at,
        #   boat_view.data_sources
        # )

        new_boat_view = %{boat_view | data_sources: new_data_sources}
        put_boat_view(socket, new_boat_view)
      end)

    socket
    # |> set_marker_position(new_position)
    |> assign(:inspect_at, new_inspect_at)
    |> push_map_state()
  end

  # defp __update_water__(%{assigns: assigns} = socket, params) do
  #   throttle? = !!params["position"]

  #   zoom_level = params["zoom_level"] || assigns.zoom_level
  #   viewport_change? = params["viewport_change"] == true

  #   t0 = assigns.first_sample_at
  #   time = assigns.inspect_at

  #   now = now_ms()
  #   diff_ms = now - assigns.last_water_event_sent_at

  #   milliseconds_diff = DateTime.diff(time, t0, :millisecond)
  #   time = NauticNet.NetCDF.epoch() + milliseconds_diff / (24 * :timer.hours(1))

  #   index = NauticNet.NetCDF.get_geodata_time_index(time)

  #   {last_water_event_index, last_water_event_sent_at, water_data} =
  #     if (index != assigns.last_water_event_index or viewport_change?) and
  #          ((throttle? and diff_ms > 33) or not throttle?) and assigns.water_visible? do
  #       %{
  #         "min_lat" => min_lat,
  #         "min_lon" => min_lon,
  #         "max_lat" => max_lat,
  #         "max_lon" => max_lon
  #       } = assigns.bounding_box

  #       data =
  #         index
  #         |> NauticNet.NetCDF.get_geodata(min_lat, max_lat, min_lon, max_lon, zoom_level)
  #         |> Base.encode64()

  #       {index, now, data}
  #     else
  #       {assigns.last_water_event_index, assigns.last_water_event_sent_at, nil}
  #     end

  #   socket
  #   |> assign(:zoom_level, zoom_level)
  #   |> assign(:last_water_event_sent_at, last_water_event_sent_at)
  #   |> assign(:last_water_event_index, last_water_event_index)
  #   |> then(fn s ->
  #     if water_data do
  #       push_event(s, "add_water_markers", %{water_data: water_data})
  #     else
  #       s
  #     end
  #   end)
  # end

  defp assign_dates_and_boats(socket) do
    [first_date | _] = dates = Playback.list_all_dates(socket.assigns.timezone)

    socket
    |> assign(:dates, dates)
    |> select_date(first_date)
  end

  # Set the date, boats, and data sources
  defp select_date(%{assigns: assigns} = socket, date) do
    boat_views =
      date
      |> Playback.list_active_boats(assigns.timezone)
      |> Enum.map(fn boat ->
        data_sources = Playback.list_data_sources(boat, date, assigns.timezone)
        coordinates = Playback.list_coordinates(boat, date, assigns.timezone, data_sources)

        %BoatView{
          boat: boat,
          data_sources: data_sources,
          coordinates: coordinates,
          track_color: track_color(boat.id)
        }
      end)

    # Set up the range for the main slider
    {first_sample_at, last_sample_at} = Playback.get_sample_range_on(date, assigns.timezone)

    map_center =
      case boat_views do
        [] -> nil
        [bv | _] -> Coordinates.get_center(bv.coordinates)
      end

    socket
    |> assign(:selected_date, date)
    |> assign(:boat_views, boat_views)
    |> assign(:first_sample_at, first_sample_at)
    |> assign(:last_sample_at, last_sample_at)
    |> assign(:range_start_at, first_sample_at)
    |> assign(:range_end_at, last_sample_at)
    |> constrain_inspect_at()
    |> push_event("configure", %{
      id: "range-slider",
      min: DateTime.to_unix(first_sample_at),
      max: DateTime.to_unix(last_sample_at)
    })
    |> push_boat_views()
    |> push_map_state()
    |> select_boat_view(nil)
    |> set_map_view(map_center)
  end

  # Ensure inspect_at lies within the range
  defp constrain_inspect_at(%{assigns: assigns} = socket) do
    inspect_at = assigns.range_end_at
    #   cond do
    #     DateTime.compare(assigns.inspect_at, assigns.range_start_at) == :lt ->
    #       assigns.range_start_at

    #     DateTime.compare(assigns.inspect_at, assigns.range_end_at) == :gt ->
    #       assigns.range_end_at

    #     :else ->
    #       assigns.inspect_at
    #   end

    assign(socket, :inspect_at, inspect_at)
  end

  defp select_boat_view(socket, nil) do
    socket
    |> assign(:selected_boat_view, nil)
    |> assign(:data_sources_modal_visible?, false)
  end

  defp select_boat_view(socket, boat_id) do
    boat_view = Enum.find(socket.assigns.boat_views, &(&1.boat.id == boat_id))

    assign(socket, :selected_boat_view, boat_view)
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

  defp boat_options(boat_views) do
    Enum.map(boat_views, &{&1.boat.name, &1.boat.id})
  end

  defp date_options(dates) do
    Enum.map(dates, &Date.to_iso8601/1)
  end

  defp sensor_options([]), do: [{"Not Available", ""}]

  defp sensor_options(sensors) do
    [{"Off", ""}] ++ Enum.map(sensors, &{&1.name, &1.id})
  end

  defp get_latest_sample(data_sources, data_source_id) do
    case Enum.find(data_sources, &(&1.id == data_source_id)) do
      %DataSource{latest_sample: %Sample{} = sample} -> sample
      _ -> nil
    end
  end

  attr :label, :string, required: true
  attr :sample, :map, required: true
  attr :field, :atom, required: true, values: [:angle_rad, :depth_m, :speed_m_s]
  attr :unit, :atom, required: true, values: [:deg, :kn, :ft]

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

  defp set_map_view(socket, nil) do
    socket
  end

  defp set_map_view(socket, {latitude, longitude}) do
    push_event(socket, "map_view", %{latitude: latitude, longitude: longitude})
  end

  defp put_boat_view(
         %{assigns: %{boat_views: boat_views, selected_boat_view: selected_boat_view}} = socket,
         %{boat: %{id: boat_id}} = new_boat_view
       ) do
    new_boat_views =
      Enum.map(boat_views, fn
        %{boat: %{id: ^boat_id}} -> new_boat_view
        boat_view -> boat_view
      end)

    new_selected_boat_view =
      case selected_boat_view do
        %{boat: %{id: ^boat_id}} -> new_boat_view
        boat_view -> boat_view
      end

    socket
    |> assign(:boat_views, new_boat_views)
    |> assign(:selected_boat_view, new_selected_boat_view)
  end

  defp update_boat_view(socket, boat_id, fun) do
    boat_view = Enum.find(socket.assigns.boat_views, &(&1.boat.id == boat_id))

    new_boat_view = fun.(boat_view)

    put_boat_view(socket, new_boat_view)
  end

  defp data_sources(%BoatView{data_sources: data_sources}), do: data_sources
  defp data_sources(_), do: []

  defp parse_unix_datetime(param, timezone) when is_binary(param) do
    param
    |> Float.parse()
    |> elem(0)
    |> trunc()
    |> DateTime.from_unix!()
    |> Timex.to_datetime(timezone)
  end

  defp track_color(boat_id) do
    red =
      boat_id
      |> :erlang.phash2(256)
      |> Integer.to_string(16)
      |> String.pad_leading(2, "0")

    green =
      boat_id
      |> String.upcase()
      |> :erlang.phash2(256)
      |> Integer.to_string(16)
      |> String.pad_leading(2, "0")

    blue =
      boat_id
      |> String.reverse()
      |> :erlang.phash2(256)
      |> Integer.to_string(16)
      |> String.pad_leading(2, "0")

    "##{red}#{green}#{blue}"
  end
end
