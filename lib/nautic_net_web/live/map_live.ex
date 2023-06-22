defmodule NauticNetWeb.MapLive do
  use NauticNetWeb, :live_view

  alias Phoenix.PubSub
  alias NauticNet.Coordinates
  alias NauticNet.Playback
  alias NauticNet.Playback.Channel
  alias NauticNet.Playback.Signal
  alias NauticNet.Racing.Boat

  require Logger

  @hingham_bounding_box %{
    "min_lat" => 42.1666,
    "max_lat" => 42.4093,
    "min_lon" => -71.0473,
    "max_lon" => -70.8557
  }

  @signal_views [
    %{type: :true_heading, label: "True Heading", field: :angle, unit: :deg},
    %{type: :velocity_over_ground, label: "COG", field: :angle, unit: :deg},
    %{type: :speed_through_water, label: "Speed Thru Water", field: :magnitude, unit: :kn},
    %{type: :velocity_over_ground, label: "SOG", field: :magnitude, unit: :kn},
    %{type: :apparent_wind, label: "Apparent Wind", field: :angle, unit: :deg},
    %{type: :water_depth, label: "Depth", field: :magnitude, unit: :ft},
    %{type: :battery, label: "Battery", field: :magnitude, unit: :percent, precision: 0},
    %{type: :heel, label: "Heel", field: :angle, unit: :deg},
    %{type: :magnetic_heading, label: "Magnetic Heading", field: :angle, unit: :deg},
    %{type: :rssi, label: "RSSI", field: :magnitude, unit: :dbm, precision: 0}
  ]

  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(NauticNet.PubSub, "leaflet")

    socket =
      socket
      # UI toggles
      |> assign(:tracks_visible?, true)
      |> assign(:water_visible?, false)
      |> assign(:is_live?, false)
      |> assign(:signals_modal_visible?, false)

      # Water currents
      |> assign(:last_water_event_sent_at, now_ms())
      |> assign(:last_water_event_index, nil)

      # Data
      |> assign(:signals, [])
      |> assign(:signal_views, @signal_views)

      # Map
      |> assign(:bounding_box, @hingham_bounding_box)
      |> assign(:zoom_level, 15)

      # Timeline
      |> assign(:inspect_at, DateTime.utc_now())
      |> assign(:timezone, "America/New_York")
      |> assign_dates_and_boats()

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

    new_signals =
      Enum.map(socket.assigns.signals, fn
        %Signal{channel: %{type: :position, boat: %{id: ^boat_id}}} = signal ->
          %{signal | visible?: visible?}

        signal ->
          signal
      end)

    socket =
      socket
      |> assign(:signals, new_signals)
      |> push_event("set_boat_visible", %{boat_id: boat_id, visible: visible?})

    {:noreply, socket}
  end

  def handle_event("select_date", %{"date" => date_param}, socket) do
    date = Date.from_iso8601!(date_param)

    {:noreply, select_date(socket, date)}
  end

  def handle_event("select_boat", %{"boat_id" => boat_id}, socket) do
    {:noreply, select_boat(socket, boat_id)}
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

  def handle_event("change_signal_visibility", params, %{assigns: assigns} = socket) do
    new_signals =
      for signal <- assigns.signals do
        %{signal | visible?: params[signal.channel.id] == "true"}
      end

    # Set track visibility on map if a :position signal's visibility was changed
    socket =
      assigns.signals
      |> Enum.zip(new_signals)
      |> Enum.reduce(socket, fn {old_signal, new_signal}, socket ->
        if new_signal.channel.type == :position and old_signal.visible? != new_signal.visible? do
          push_event(socket, "set_boat_visible", %{
            boat_id: new_signal.channel.boat.id,
            visible: new_signal.visible?
          })
        else
          socket
        end
      end)

    {:noreply, assign(socket, :signals, new_signals)}
  end

  def handle_event("show_signals_modal", _, socket) do
    {:noreply, assign(socket, :signals_modal_visible?, true)}
  end

  def handle_event("hide_signals_modal", _, socket) do
    {:noreply, assign(socket, :signals_modal_visible?, false)}
  end

  # PubSub message from NauticNet.Ingest
  def handle_info({:new_samples, samples}, socket) do
    # Only care about samples that are "today"
    samples =
      Enum.filter(samples, fn s -> DateTime.to_date(s.time) == socket.assigns.selected_date end)

    IO.inspect("#{length(samples)} new samples")
    # TODO: Push samples to JS

    {:noreply, socket}
  end

  defp push_boat_coordinates(socket) do
    boat_views =
      for %Signal{channel: %Channel{type: :position}} = signal <- socket.assigns.signals do
        %{
          "boat_id" => signal.channel.boat.id,
          "track_color" => signal.color,
          "coordinates" =>
            Enum.map(signal.coordinates, fn coord ->
              %{
                "time" => DateTime.to_unix(coord.time),
                "lat" => coord.latitude,
                "lng" => coord.longitude,
                "heading_rad" => coord.true_heading
              }
            end)
        }
      end

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

    new_signals = Playback.fill_latest_samples(assigns.signals, new_inspect_at)

    socket
    |> assign(:signals, new_signals)
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
    dates = Playback.list_all_dates(socket.assigns.timezone)

    socket
    |> assign(:dates, dates)
    |> select_date(List.last(dates))
  end

  # Set the date, boats, and data sources
  defp select_date(socket, nil) do
    now = DateTime.utc_now()

    socket
    |> assign(:selected_date, nil)
    |> unsubscribe_from_boats()
    |> assign(:signals, [])
    |> select_boat(nil)
    |> assign(:first_sample_at, now)
    |> assign(:last_sample_at, now)
    |> assign(:range_start_at, now)
    |> assign(:range_end_at, now)
  end

  defp select_date(%{assigns: assigns} = socket, date) do
    signals =
      date
      |> Playback.list_channels_on(assigns.timezone)
      |> Enum.map(fn
        %Channel{type: :position, boat: boat} = channel ->
          coordinates = Playback.list_coordinates(channel, date, assigns.timezone)
          %Signal{channel: channel, coordinates: coordinates, color: boat_color(boat.id)}

        %Channel{boat: boat} = channel ->
          %Signal{channel: channel, color: boat_color(boat.id)}
      end)

    # Set up the range for the main slider
    {first_sample_at, last_sample_at} = Playback.get_sample_range_on(date, assigns.timezone)

    first_position_signal = Enum.find(signals, &(&1.channel.type == :position))

    map_center =
      first_position_signal && Coordinates.get_center(first_position_signal.coordinates)

    socket
    |> assign(:selected_date, date)
    |> unsubscribe_from_boats()
    |> assign(:signals, signals)
    |> subscribe_to_boats()
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
    |> push_boat_coordinates()
    |> push_map_state()
    |> select_boat(first_position_signal)
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

  defp select_boat(socket, nil) do
    socket
    |> assign(:selected_boat, nil)
    |> assign(:signals_modal_visible?, false)
  end

  defp select_boat(socket, %Signal{channel: %Channel{boat: boat}}), do: select_boat(socket, boat)
  defp select_boat(socket, %Channel{boat: boat}), do: select_boat(socket, boat)
  defp select_boat(socket, %Boat{} = boat), do: assign(socket, :selected_boat, boat)

  defp select_boat(socket, boat_id) when is_binary(boat_id) do
    signal = Enum.find(socket.assigns.signals, &(&1.channel.boat.id == boat_id))

    select_boat(socket, signal.channel.boat)
  end

  # <select> option helpers

  defp boat_options(signals) do
    signals
    |> Enum.map(&{&1.channel.boat.name, &1.channel.boat.id})
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp date_options(dates) do
    Enum.map(dates, &Date.to_iso8601/1)
  end

  attr :label, :string, required: true
  attr :signal, Signal, required: true
  attr :field, :atom, required: true, values: [:angle, :magnitude]
  attr :unit, :atom, required: true, values: [:deg, :kn, :ft]
  attr :precision, :integer, required: false
  attr :show_sensor, :boolean, required: false, default: true

  defp signal_view(assigns) do
    assigns =
      assign_new(assigns, :precision, fn ->
        if assigns.unit == :deg, do: 0, else: 1
      end)

    channel_unit = if assigns.unit == :deg, do: :rad, else: assigns.signal.channel.unit

    display_value =
      if assigns.signal.latest_sample do
        assigns.signal.latest_sample
        |> Map.fetch!(assigns.field)
        |> convert(channel_unit, assigns.unit)
        |> :erlang.float_to_binary(decimals: assigns.precision)
      else
        "--"
      end

    assigns = assign(assigns, display_value: display_value)

    ~H"""
    <div class="border rounded-lg p-2 flex flex-col">
      <div class="flex justify-between font-semibold text-sm">
        <div class="font-bold"><%= @label %></div>
        <div><%= unit(@unit) %></div>
      </div>
      <div class="text-center text-4xl flex-grow flex items-center justify-center py-2">
        <%= @display_value %>
      </div>
      <%= if @show_sensor do %>
        <div class="text-center text-sm text-gray-400 font-medium">
          <%= @signal.channel.sensor.name %>
        </div>
      <% end %>
    </div>
    """
  end

  defp unit(:percent), do: "%"
  defp unit(:dbm), do: "dBm"
  defp unit(:deg), do: "°"
  defp unit(:kn), do: "kn"
  defp unit(:ft), do: "ft"

  defp convert(value, same, same), do: value * 1.0
  defp convert(value, :m_s, :kn), do: value * 1.94384
  defp convert(value, :rad, :deg), do: value * 180 / :math.pi()
  defp convert(value, :m, :ft), do: value * 3.28084

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp set_map_view(socket, nil) do
    socket
  end

  defp set_map_view(socket, {latitude, longitude}) do
    push_event(socket, "map_view", %{latitude: latitude, longitude: longitude})
  end

  defp parse_unix_datetime(param, timezone) when is_binary(param) do
    param
    |> Float.parse()
    |> elem(0)
    |> trunc()
    |> DateTime.from_unix!()
    |> Timex.to_datetime(timezone)
  end

  defp boat_color(boat_id) do
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

  defp subscribe_to_boats(socket) do
    for boat <- boats(socket.assigns.signals) do
      Phoenix.PubSub.subscribe(NauticNet.PubSub, "boat:#{boat.id}")
    end

    socket
  end

  defp unsubscribe_from_boats(socket) do
    for boat <- boats(socket.assigns.signals) do
      Phoenix.PubSub.unsubscribe(NauticNet.PubSub, "boat:#{boat.id}")
    end

    socket
  end

  defp boats(signals) do
    signals |> Enum.map(& &1.channel.boat) |> Enum.uniq()
  end

  defp position_signals(signals) do
    Enum.filter(signals, &(&1.channel.type == :position))
  end

  defp boat_count(signals) do
    signals |> Enum.map(& &1.channel.boat.id) |> Enum.uniq() |> length()
  end

  defp boat_signal_count(boat, signals) do
    boat |> boat_signals(signals) |> length()
  end

  defp visible_boat_signal_count(boat, signals) do
    boat |> visible_boat_signals(signals) |> length()
  end

  defp boat_signals(nil, _signals), do: []

  defp boat_signals(boat, signals) do
    signals
    |> Enum.filter(&(&1.channel.boat.id == boat.id))
    |> Enum.sort_by(& &1.channel.name)
  end

  defp visible_boat_signals(boat, signals) do
    boat |> boat_signals(signals) |> Enum.filter(& &1.visible?)
  end

  defp visible_boat_signals(boat, signals, type) do
    boat |> boat_signals(signals) |> Enum.filter(&(&1.visible? and &1.channel.type == type))
  end

  defp all_same_sensor?(signals) do
    signals |> Enum.map(& &1.channel.sensor.id) |> Enum.uniq() |> length() <= 1
  end
end
