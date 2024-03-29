defmodule NauticNetWeb.MapLive do
  use NauticNetWeb, :live_view

  alias NauticNet.LocalDate
  alias NauticNet.Playback
  alias NauticNet.Playback.Channel
  alias NauticNet.Playback.Signal
  alias NauticNet.Racing.Boat
  alias Phoenix.PubSub

  require Logger

  @default_bounding_box %{
    "min_lat" => 42.1666,
    "max_lat" => 42.4093,
    "min_lon" => -71.0473,
    "max_lon" => -70.8557
  }

  @timezone "America/New_York"

  @signal_views [
    %{type: :true_heading, label: "Compass Heading (True)", field: :angle, unit: :deg_true},
    %{
      type: :magnetic_heading,
      label: "Compass Heading (Magnetic)",
      field: :angle,
      unit: :deg_magnetic
    },
    %{type: :velocity_over_ground, label: "COG", field: :angle, unit: :deg},
    %{type: :speed_through_water, label: "Speed Thru Water", field: :magnitude, unit: :kn},
    %{type: :velocity_over_ground, label: "SOG", field: :magnitude, unit: :kn},
    %{type: :apparent_wind, label: "Apparent Wind", field: :angle, unit: :deg},
    %{type: :apparent_wind, label: "Apparent Wind", field: :magnitude, unit: :kn},
    %{type: :water_depth, label: "Depth", field: :magnitude, unit: :ft},
    %{type: :battery, label: "Battery", field: :magnitude, unit: :percent, precision: 0},
    %{type: :heel, label: "Heel", field: :angle, unit: :deg},
    %{type: :rssi, label: "RSSI", field: :magnitude, unit: :dbm, precision: 0},
    %{type: :yaw, label: "Yaw", field: :angle, unit: :deg},
    %{type: :pitch, label: "Pitch", field: :angle, unit: :deg},
    %{type: :roll, label: "Roll", field: :angle, unit: :deg}
  ]

  def mount(params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(NauticNet.PubSub, "leaflet")

    socket =
      socket
      # UI toggles
      |> assign(:tracks_visible?, true)
      |> assign(:water_visible?, false)
      |> assign(:live?, false)
      |> assign(:signals_modal_visible?, false)

      # Water currents
      |> assign(:last_water_event_sent_at, now_ms())
      |> assign(:last_water_event_index, nil)

      # Data
      |> assign(:signals, [])
      |> assign(:signal_views, @signal_views)

      # Map
      |> assign(:needs_centering?, true)
      |> assign(:bounding_box, @default_bounding_box)
      |> assign(:zoom_level, 15)
      |> assign(:play, false)

      # selected_boat
      |> assign(:selected_boat, nil)
      |> assign(:signals_modal_visible?, false)

      # Timeline
      |> select_date(params)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(date: params["date"])
      |> assign(from: params["from"])
      |> assign(to: params["to"])
      |> assign(playback: params["playback"])
      |> assign(speed: params["speed"])
      |> assign(boats: selected_boats(params["boats"]))

    {:noreply, socket}
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

  def handle_event("inc_playback_speed", _params, socket) do
    speed = socket.assigns.playback_speed * 2

    speed =
      if speed <= 32 do
        speed
      else
        socket.assigns.playback_speed
      end

    query_params =
      %{
        date: socket.assigns.date,
        from: to_time(socket.assigns.range_start_at),
        to: to_time(socket.assigns.range_end_at),
        playback: to_time(socket.assigns.inspect_at),
        speed: speed,
        boats: socket.assigns.boats
      }
      |> Plug.Conn.Query.encode()

    socket =
      socket
      |> assign(playback_speed: speed)
      |> push_patch(to: "/?#{query_params}", replace: true)

    {:noreply, socket}
  end

  def handle_event("dec_playback_speed", _params, socket) do
    speed = (socket.assigns.playback_speed / 2) |> round()

    speed =
      if speed >= 1 do
        speed
      else
        socket.assigns.playback_speed
      end

    query_params =
      %{
        date: socket.assigns.date,
        from: to_time(socket.assigns.range_start_at),
        to: to_time(socket.assigns.range_end_at),
        playback: to_time(socket.assigns.inspect_at),
        speed: speed,
        boats: socket.assigns.boats
      }
      |> Plug.Conn.Query.encode()

    socket =
      socket
      |> assign(playback_speed: speed)
      |> push_patch(to: "/?#{query_params}", replace: true)

    {:noreply, socket}
  end

  def handle_event("update_from", %{"from" => from}, %{assigns: assigns} = socket) do
    first_sample_time = to_time(assigns.first_sample_at) |> Time.from_iso8601!()
    from = validate_time_input(from, first_sample_time)

    from = validate_from(assigns, from)

    range_start_at = build_datetime(assigns.date, from, assigns.first_sample_at)
    range_end_at = build_datetime(assigns.date, assigns.to, assigns.last_sample_at)

    query_params =
      %{
        date: assigns.date,
        from: from,
        to: assigns.to,
        playback: to_time(assigns.inspect_at),
        speed: assigns.playback_speed,
        boats: assigns.boats
      }
      |> Plug.Conn.Query.encode()

    socket =
      socket
      |> assign(:range_start_at, range_start_at)
      |> assign(:range_end_at, range_end_at)
      |> assign(:from, from)
      |> push_event("configure", %{
        id: "range-slider",
        min: DateTime.to_unix(range_start_at),
        max: DateTime.to_unix(range_end_at)
      })
      |> push_patch(to: "/?#{query_params}", replace: true)

    {:noreply, socket}
  end

  def handle_event("update_to", %{"to" => to}, %{assigns: assigns} = socket) do
    last_sample_time = to_time(assigns.last_sample_at) |> Time.from_iso8601!()
    to = validate_time_input(to, last_sample_time)

    to = validate_to(assigns, to)

    range_start_at = build_datetime(assigns.date, assigns.from, assigns.first_sample_at)
    range_end_at = build_datetime(assigns.date, to, assigns.last_sample_at)

    query_params =
      %{
        date: assigns.date,
        from: assigns.from,
        to: to,
        playback: to_time(assigns.inspect_at),
        speed: assigns.playback_speed,
        boats: assigns.boats
      }
      |> Plug.Conn.Query.encode()

    socket =
      socket
      |> assign(:range_start_at, range_start_at)
      |> assign(:range_end_at, range_end_at)
      |> assign(:to, to)
      |> push_event("configure", %{
        id: "range-slider",
        min: DateTime.to_unix(range_start_at),
        max: DateTime.to_unix(range_end_at)
      })
      |> push_patch(to: "/?#{query_params}", replace: true)

    {:noreply, socket}
  end

  def handle_event("update_playback", %{"playback" => playback}, %{assigns: assigns} = socket) do
    range_start_time = to_time(assigns.range_start_at) |> Time.from_iso8601!()
    range_end_time = to_time(assigns.range_end_at) |> Time.from_iso8601!()
    playback = validate_time_input(playback, range_end_time)

    playback2 =
      case Time.from_iso8601(playback) do
        {:ok, playback} -> playback
        _ -> range_start_time
      end

    playback =
      case Time.compare(playback2, range_start_time) do
        :lt ->
          Time.to_string(range_start_time)

        _ ->
          case Time.compare(playback2, range_end_time) do
            :gt -> Time.to_string(range_end_time)
            _ -> playback
          end
      end

    playback_dt =
      build_datetime(assigns.date, playback, assigns.inspect_at)
      |> DateTime.to_unix()

    new_inspect_at = parse_unix_datetime(playback_dt, assigns.local_date.timezone)

    query_params =
      %{
        date: assigns.date,
        from: assigns.from,
        to: assigns.to,
        playback: playback,
        speed: assigns.playback_speed,
        boats: assigns.boats
      }
      |> Plug.Conn.Query.encode()

    socket =
      socket
      |> assign(:inspect_at, new_inspect_at)
      |> assign(:playback, playback)
      |> push_patch(to: "/?#{query_params}", replace: true)

    {:noreply, socket}
  end

  def handle_event("update_range", %{"min" => min, "max" => max}, socket) do
    range_start_at = parse_unix_datetime(min, socket.assigns.local_date.timezone)
    range_end_at = parse_unix_datetime(max, socket.assigns.local_date.timezone)

    query_params =
      %{
        date: default_date(socket.assigns.date),
        from: to_time(range_start_at),
        to: to_time(range_end_at),
        playback: to_time(socket.assigns.inspect_at),
        speed: socket.assigns.playback_speed,
        boats: socket.assigns.boats
      }
      |> Plug.Conn.Query.encode()

    {:noreply,
     socket
     |> assign(:range_start_at, range_start_at)
     |> assign(:range_end_at, range_end_at)
     |> constrain_inspect_at()
     |> push_map_state()
     |> push_patch(to: "/?#{query_params}", replace: true)}
  end

  def handle_event("set_boat_visible", %{"boat-id" => boat_id} = params, socket) do
    visible? = params["value"] == "on"

    new_boats =
      if visible? do
        [boat_id | socket.assigns.boats]
      else
        Enum.filter(socket.assigns.boats, fn bid -> bid != boat_id end)
      end

    new_signals =
      Enum.map(socket.assigns.signals, fn
        %Signal{channel: %{type: :position, boat: %{id: ^boat_id}}} = signal ->
          %{signal | visible?: visible?}

        signal ->
          signal
      end)

    query_params =
      %{
        date: socket.assigns.date,
        from: socket.assigns.from,
        to: socket.assigns.to,
        playback: socket.assigns.playback,
        speed: socket.assigns.playback_speed,
        boats: new_boats
      }
      |> Plug.Conn.Query.encode()

    socket =
      socket
      |> assign(:signals, new_signals)
      |> assign(:boats, new_boats)
      |> push_event("set_boat_visible", %{boat_id: boat_id, visible: visible?})
      |> push_patch(to: "/?#{query_params}", replace: true)

    {:noreply, socket}
  end

  def handle_event("select_date", params, socket) do
    socket = select_date(socket, params)
    %{assigns: assigns} = socket

    query_params =
      %{
        date: assigns.date,
        from: assigns.from,
        to: assigns.to,
        playback: assigns.playback,
        speed: assigns.playback_speed,
        boats: assigns.boats
      }
      |> Plug.Conn.Query.encode()

    socket = push_patch(socket, to: "/?#{query_params}", replace: true)

    {:noreply, socket}
  end

  def handle_event("select_boat", %{"boat_id" => boat_id}, socket) do
    {:noreply, select_boat(socket, boat_id)}
  end

  def handle_event("live_changed", %{"live" => live_param}, socket) do
    live? = live_param == "true"

    if live?, do: send(self(), :live_tick)

    {
      :noreply,
      socket
      |> assign(:live?, live?)
      # RangeSlider state must be updated via JS hook because it has phx-update="ignore"
      |> push_event("set_enabled", %{id: "range-slider", enabled: not live?})
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
        if signal.channel.boat.id == params["selected_boat_id"] do
          %{signal | visible?: params[signal.channel.id] == "true"}
        else
          %{signal | visible?: signal.visible? || params[signal.channel.id] == "true"}
        end
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

  def handle_event("show_signals_modal", %{"boat-id" => boat_id}, socket) do
    signal =
      socket.assigns.signals
      |> Enum.find(fn %Signal{channel: %Channel{boat: boat}} -> boat.id == boat_id end)

    socket =
      socket
      |> assign(:signals_modal_visible?, true)
      |> assign(:selected_boat, signal.channel.boat)

    {:noreply, socket}
  end

  def handle_event("hide_signals_modal", _, socket) do
    {:noreply, assign(socket, :signals_modal_visible?, false)}
  end

  def handle_event("remove_inspector", %{"boat-id" => boat_id}, socket) do
    inspected_boats =
      socket.assigns.inspected_boats
      |> Enum.filter(fn boat -> boat.id != boat_id end)

    socket = assign(socket, :inspected_boats, inspected_boats)

    {:noreply, socket}
  end

  # PubSub message from NauticNet.Ingest
  # def handle_info({:new_samples, samples}, %{assigns: %{live?: true} = assigns} = socket) do
  #   # Only care about samples that are "today"
  #   samples = Enum.filter(samples, fn s -> DateTime.to_date(s.time) == assigns.local_date end)

  #   # Update the latest_sample for applicable signals
  #   signals =
  #     for signal <- assigns.signals do
  #       if new_sample = Enum.find(samples, &Sample.in_channel?(&1, signal.channel)) do
  #         %{signal | latest_sample: new_sample}
  #       else
  #         signal
  #       end
  #     end

  #   # for %{type: :position} = position_sample <- samples do
  #   # TODO: Push coordinate samples to JS
  #   # end

  #   {:noreply, assign(socket, :signals, signals)}
  # end

  # def handle_info({:new_samples, _samples}, %{assigns: %{live?: false}} = socket) do
  #   # TODO: Something??

  #   {:noreply, socket}
  # end

  def handle_info({:new_samples, _}, socket) do
    {:noreply, socket}
  end

  # Set to "now" if Live is enabled
  def handle_info(:live_tick, %{assigns: %{live?: true}} = socket) do
    Process.send_after(self(), :live_tick, :timer.seconds(1))

    {:noreply, set_live_position(socket)}
  end

  # Ignore if Live mode has been disabled
  def handle_info(:live_tick, %{assigns: %{live?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:start_coordinate_tasks, socket) do
    live_view_pid = self()

    socket.assigns.signals
    |> position_signals()
    |> Enum.each(fn signal ->
      Task.start(fn ->
        fetch_coordinates_task(signal, socket.assigns.local_date, live_view_pid)
      end)
    end)

    {:noreply, socket}
  end

  def handle_info({:push_boat_view, boat_view, center_coord}, socket) do
    boat_id = boat_view["boat_id"]
    visible? = boat_id in socket.assigns.boats

    socket =
      socket
      |> push_event("add_boat_view", %{"boat_view" => boat_view})
      |> push_event("set_boat_visible", %{boat_id: boat_id, visible: visible?})
      # Needed to set time bounds for polyline
      |> push_map_state()
      |> maybe_recenter_map(center_coord)

    {:noreply, socket}
  end

  defp fetch_coordinates_task(signal, local_date, live_view_pid) do
    coordinates =
      Playback.list_coordinates(
        signal.channel,
        local_date
      )

    boat_view = %{
      "boat_id" => signal.channel.boat.id,
      "boat_name" => signal.channel.boat.name,
      "track_color" => signal.color,
      "coordinates" =>
        Enum.map(coordinates, fn coord ->
          %{
            "time" => DateTime.to_unix(coord.time),
            "lat" => coord.latitude,
            "lng" => coord.longitude,
            "heading_deg" => coord.magnetic_heading
          }
        end)
    }

    center_coord =
      if coordinates == [] do
        nil
      else
        {min_lat, max_lat} = coordinates |> Enum.map(& &1.latitude) |> Enum.min_max()
        {min_lon, max_lon} = coordinates |> Enum.map(& &1.longitude) |> Enum.min_max()
        {(min_lat + max_lat) / 2, (min_lon + max_lon) / 2}
      end

    send(live_view_pid, {:push_boat_view, boat_view, center_coord})

    :ok
  end

  defp maybe_recenter_map(socket, center_coord) do
    if socket.assigns.needs_centering? and center_coord != nil do
      socket
      |> set_map_view(center_coord)
      |> assign(:needs_centering?, false)
    else
      socket
    end
  end

  defp push_boat_coordinates(socket) do
    if connected?(socket) do
      send(self(), :start_coordinate_tasks)

      socket
      |> assign(:needs_centering?, true)
      |> push_event("clear_boat_views", %{})
    else
      socket
    end
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
        parse_unix_datetime(pos, assigns.local_date.timezone)
      else
        assigns.inspect_at
      end

    query_params =
      %{
        date: socket.assigns.date,
        from: to_time(socket.assigns.range_start_at),
        to: to_time(socket.assigns.range_end_at),
        playback: to_time(new_inspect_at),
        speed: socket.assigns.playback_speed,
        boats: socket.assigns.boats
      }
      |> Plug.Conn.Query.encode()

    new_signals = Playback.fill_latest_samples(assigns.signals, new_inspect_at)

    socket
    |> assign(:signals, new_signals)
    |> assign(:inspect_at, new_inspect_at)
    |> assign(:play, params["play"])
    |> push_map_state()
    |> push_patch(to: "/?#{query_params}", replace: true)
  end

  defp set_live_position(socket) do
    end_at = DateTime.utc_now()
    start_at = DateTime.add(end_at, -3600, :second)

    new_signals = Playback.fill_latest_samples(socket.assigns.signals, end_at)

    socket
    |> assign(:signals, new_signals)
    |> assign(:inspect_at, end_at)
    # |> assign(:first_sample_at, start_at)
    |> assign(:last_sample_at, end_at)
    |> assign(:range_start_at, start_at)
    |> assign(:range_end_at, end_at)
    |> push_map_state()
    |> push_live_coordinates()

    # |> push_event("configure", %{
    #   id: "range-slider",
    #   min: DateTime.to_unix(start_at),
    #   max: DateTime.to_unix(end_at)
    # })
  end

  defp push_live_coordinates(socket) do
    # TODO: Push new coordinates
    socket
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

  # Set the date, boats, and data sources
  defp select_date(socket, params) do
    date = default_date(params["date"])
    local_date = %LocalDate{date: date, timezone: @timezone}
    selected_boats = selected_boats(params["boats"])

    signals =
      local_date
      |> Playback.list_channels_on()
      |> Enum.map(fn %Channel{boat: boat} = channel ->
        signal = %Signal{channel: channel, color: boat_color(boat.id)}

        case signal do
          %Signal{channel: %{type: :position, boat: %{id: boat_id}}} = signal ->
            %{signal | visible?: boat_id in selected_boats}

          signal ->
            signal
        end
      end)

    # Set up the range for the main slider
    {first_sample_at, last_sample_at} = Playback.get_sample_range_on(local_date)

    from = params["from"] || "00:00:00"
    to = params["to"] || "23:59:59"
    playback = params["playback"] || "23:59:59"

    range_start_at = build_datetime(params["date"], from, first_sample_at)
    range_end_at = build_datetime(params["date"], to, last_sample_at)
    playback = build_datetime(params["date"], playback, last_sample_at)

    speed = parse_speed(params)

    socket
    |> assign(:local_date, local_date)
    |> assign(:date, Date.to_string(local_date.date))
    |> unsubscribe_from_boats()
    |> assign(:signals, signals)
    |> subscribe_to_boats()
    |> assign(:first_sample_at, first_sample_at)
    |> assign(:last_sample_at, last_sample_at)
    |> assign(:range_start_at, range_start_at)
    |> assign(:from, range_start_at)
    |> assign(:range_end_at, range_end_at)
    |> assign(:to, range_end_at)
    |> assign(:inspect_at, playback)
    |> assign(:playback, playback)
    |> assign(:playback_speed, speed)
    |> assign(:boats, selected_boats)
    |> assign(:inspected_boats, [])
    |> constrain_inspect_at()
    |> push_event("configure_date", %{
      id: "range-slider",
      min: DateTime.to_unix(first_sample_at),
      max: DateTime.to_unix(last_sample_at)
    })
    |> push_boat_coordinates()
    |> push_map_state()
  end

  # Ensure inspect_at lies within the range
  defp constrain_inspect_at(%{assigns: assigns} = socket) do
    inspect_at =
      cond do
        DateTime.compare(assigns.inspect_at, assigns.range_start_at) == :lt ->
          assigns.range_start_at

        DateTime.compare(assigns.inspect_at, assigns.range_end_at) == :gt ->
          assigns.range_end_at

        :else ->
          assigns.inspect_at
      end

    assign(socket, :inspect_at, inspect_at)
  end

  defp select_boat(socket, nil) do
    socket
    |> assign(:selected_boat, nil)
    |> assign(:signals_modal_visible?, false)
  end

  defp select_boat(socket, %Signal{channel: %Channel{boat: boat}}), do: select_boat(socket, boat)
  defp select_boat(socket, %Channel{boat: boat}), do: select_boat(socket, boat)

  defp select_boat(socket, %Boat{} = boat) do
    inspected_boats = socket.assigns.inspected_boats ++ [boat]

    socket
    |> assign(:selected_boat, boat)
    |> assign(:inspected_boats, inspected_boats)
  end

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

  defp build_datetime(nil, _time, default), do: default
  defp build_datetime(_date, nil, default), do: default

  defp build_datetime(date, time, _default) do
    date = default_date(date)

    time =
      case Time.from_iso8601(time) do
        {:ok, time} -> Time.to_string(time)
        _ -> "00:00:00"
      end

    "#{date}T#{time}"
    |> NaiveDateTime.from_iso8601!()
    |> Timex.to_datetime(@timezone)
  end

  defp default_date(nil), do: Timex.today(@timezone)

  defp default_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> date
      _ -> Timex.today(@timezone)
    end
  end

  defp to_time(dt) do
    dt
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.split(".")
    |> List.first()
  end

  defp selected_boats(boats) do
    if is_list(boats), do: boats, else: []
  end

  attr(:label, :string, required: true)
  attr(:signal, Signal, required: true)
  attr(:field, :atom, required: true, values: [:angle, :magnitude])
  attr(:unit, :atom, required: true, values: [:deg, :deg_magnetic, :deg_true, :kn, :ft])
  attr(:precision, :integer, required: false)
  attr(:show_sensor, :boolean, required: false, default: true)

  defp signal_view(assigns) do
    assigns =
      assign_new(assigns, :precision, fn ->
        if assigns.unit in [:deg, :deg_magnetic, :deg_true], do: 0, else: 1
      end)

    channel_unit =
      if assigns.unit in [:deg, :deg_magnetic, :deg_true],
        do: :rad,
        else: assigns.signal.channel.unit

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
  defp unit(:deg_magnetic), do: "°M"
  defp unit(:deg_true), do: "°T"
  defp unit(:kn), do: "kn"
  defp unit(:ft), do: "ft"

  defp convert(value, same, same), do: value * 1.0
  defp convert(value, :m_s, :kn), do: value * 1.94384

  defp convert(value, :rad, deg) when deg in [:deg, :deg_magnetic, :deg_true],
    do: value * 180 / :math.pi()

  defp convert(value, :m, :ft), do: value * 3.28084

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp set_map_view(socket, {latitude, longitude}) do
    push_event(socket, "map_view", %{latitude: latitude, longitude: longitude})
  end

  defp parse_unix_datetime(param, local_timezone) when is_binary(param) do
    param
    |> Float.parse()
    |> elem(0)
    |> trunc()
    |> parse_unix_datetime(local_timezone)
  end

  defp parse_unix_datetime(param, local_timezone) when is_integer(param) do
    param
    |> DateTime.from_unix!()
    |> Timex.to_datetime(local_timezone)
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
    if connected?(socket) do
      for boat <- boats(socket.assigns.signals) do
        NauticNet.PubSub.subscribe_to_boat(boat)
      end
    end

    socket
  end

  defp unsubscribe_from_boats(socket) do
    if connected?(socket) do
      for boat <- boats(socket.assigns.signals) do
        NauticNet.PubSub.unsubscribe_from_boat(boat)
      end
    end

    socket
  end

  defp boats(signals) do
    signals |> Enum.map(& &1.channel.boat) |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.name)
  end

  defp position_signals(signals) do
    Enum.filter(signals, fn
      # If primary_position_sensor_id is set, only return that sensor
      %{channel: %{type: :position, boat: %{primary_position_sensor_id: id}, sensor: %{id: id}}} ->
        true

      # if primary_position_sensor_id is not set, return all location sensors
      %{channel: %{type: :position, boat: %{primary_position_sensor_id: nil}}} ->
        true

      # Don't return non-location sensors
      _ ->
        false
    end)
    |> Enum.uniq_by(fn %{channel: %{boat: boat}} -> boat.id end)
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

  defp boat_sensor_count(boat, signals) do
    boat
    |> boat_signals(signals)
    |> Enum.map(& &1.channel.sensor.id)
    |> Enum.uniq()
    |> length()
  end

  # defp format_time(datetime) do
  #   Timex.format!(datetime, "{h12}:{m}:{s}{am} {Zabbr}")
  # end

  defp validate_from(assigns, from) do
    first_sample_time = to_time(assigns.first_sample_at) |> Time.from_iso8601!()
    last_sample_time = to_time(assigns.last_sample_at) |> Time.from_iso8601!()

    from2 =
      case Time.from_iso8601(from) do
        {:ok, from} -> from
        _ -> first_sample_time
      end

    case Time.compare(from2, first_sample_time) do
      :lt ->
        Time.to_string(first_sample_time)

      _ ->
        case Time.compare(from2, last_sample_time) do
          :gt -> Time.to_string(last_sample_time)
          _ -> from
        end
    end
  end

  defp validate_to(assigns, to) do
    first_sample_time = to_time(assigns.first_sample_at) |> Time.from_iso8601!()
    last_sample_time = to_time(assigns.last_sample_at) |> Time.from_iso8601!()

    to2 =
      case Time.from_iso8601(to) do
        {:ok, to} -> to
        _ -> last_sample_time
      end

    case Time.compare(to2, last_sample_time) do
      :gt ->
        Time.to_string(last_sample_time)

      _ ->
        case Time.compare(to2, first_sample_time) do
          :lt ->
            Time.to_string(first_sample_time)

          _ ->
            to
        end
    end
  end

  defp parse_speed(params) do
    if is_nil(params["speed"]) do
      1
    else
      case Integer.parse(params["speed"]) do
        {s, _} -> s
        _ -> 1
      end
    end
  end

  defp validate_time_input(playback, default) do
    case parse_time_input(playback) do
      [n1] ->
        expand_time(:hour, n1, default)

      [n1, n2] ->
        expand_time(:hour_min, n1, n2, default)

      [n1, n2, n3] ->
        expand_time(:hour_min_sec, n1, n2, n3, default)

      _ ->
        "#{default}"
    end
  end

  defp parse_time_input(playback) do
    playback
    |> String.trim()
    |> String.replace(~r/[^:\s0-9]/, "")
    |> String.split(":")
    |> Enum.map(fn x ->
      String.split(x, " ")
    end)
    |> List.flatten()
    |> Enum.map(fn x -> String.trim(x) end)
    |> Enum.filter(fn x -> x not in [""] end)
    |> Enum.map(fn x ->
      case Integer.parse(x) do
        {n, _str} -> n
        _ -> :error
      end
    end)
  end

  defp pad_hours(n) when n >= 0 and n <= 9, do: "0#{n}"
  defp pad_hours(n) when n >= 10 and n <= 23, do: "#{n}"
  defp pad_hours(_n), do: "00"

  defp pad_mins(n) when n >= 0 and n <= 9, do: "0#{n}"
  defp pad_mins(n) when n >= 10 and n <= 59, do: "#{n}"
  defp pad_mins(_n), do: "00"

  defp check_hours(n) when n >= 0 and n <= 23, do: true
  defp check_hours(_n), do: false

  defp check_mins(n) when n >= 0 and n <= 59, do: true
  defp check_mins(_n), do: false

  defp expand_time(:hour, n1, default) do
    if check_hours(n1) do
      "#{pad_hours(n1)}:00:00"
    else
      "#{default}"
    end
  end

  defp expand_time(:hour_min, n1, n2, default) do
    if check_hours(n1) and check_mins(n2) do
      "#{pad_hours(n1)}:#{pad_mins(n2)}:00"
    else
      "#{default}"
    end
  end

  defp expand_time(:hour_min_sec, n1, n2, n3, default) do
    if check_hours(n1) and check_mins(n2) and check_mins(n3) do
      "#{pad_hours(n1)}:#{pad_mins(n2)}:#{pad_mins(n3)}"
    else
      "#{default}"
    end
  end
end
