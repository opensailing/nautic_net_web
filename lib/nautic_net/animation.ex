defmodule NauticNet.Animation do
  @moduledoc false
  alias Phoenix.PubSub

  @initial_coordinates {42.27, -70.997}
  @step_increment 0.00005
  @timeout 1000

  def set_map_view({latitude, longitude}),
    do: send(self(), {"map_view", latitude, longitude})

  def broadcast_map_view({latitude, longitude}),
    do: PubSub.broadcast(NauticNet.PubSub, "leaflet", {"map_view", latitude, longitude})

  def set_marker_coordinates({_date, latitude, longitude}),
    do: send(self(), {"marker_coordinates", latitude, longitude})

  def set_marker_position(position),
    do: send(self(), {"marker_position", position})

  def broadcast_marker_coordinates({_date, latitude, longitude}),
    do:
      PubSub.broadcast(
        NauticNet.PubSub,
        "leaflet",
        {"marker_coordinates", latitude, longitude}
      )

  def set_track_coordinates(coordinates) do
    dateless_coordinates =
      Enum.map(coordinates, fn {_date, latitude, longitude} -> [latitude, longitude] end)

    send(self(), {"track_coordinates", dateless_coordinates})
  end

  def diagonal({lat, lng} \\ @initial_coordinates) do
    updated_coordinates = {lat + @step_increment, lng + @step_increment}

    PubSub.broadcast(
      NauticNet.PubSub,
      "leaflet",
      {"marker_coordinates", lat + @step_increment, lng + @step_increment}
    )

    Process.sleep(@timeout)

    diagonal(updated_coordinates)
  end
end
