defmodule NauticNetWeb.BoatsLive.Edit do
  use NauticNetWeb, :live_view

  alias NauticNet.Racing

  def mount(%{"id" => id}, _session, socket) do
    boat = Racing.get_boat!(id)
    changeset = Racing.change_boat(boat)

    location_sensors = Racing.list_location_sensors(boat)

    socket = assign(socket, boat: boat, changeset: changeset, location_sensors: location_sensors)

    {:ok, socket}
  end

  def handle_event("validate", %{"boat" => params}, socket) do
    changeset =
      socket.assigns.boat
      |> Racing.change_boat(params)
      |> Map.put(:action, :update)

    socket = assign(socket, changeset: changeset)

    {:noreply, socket}
  end

  def handle_event("save", %{"boat" => params}, socket) do
    socket =
      case Racing.update_boat(socket.assigns.boat, params) do
        {:ok, boat} ->
          socket
          |> assign(boat: boat, changeset: Racing.change_boat(boat))
          |> put_flash(:info, "Boat updated.")

        {:error, changeset} ->
          socket
          |> assign(changeset: changeset)
          |> put_flash(:error, "Boat not saved.")
      end

    {:noreply, socket}
  end

  defp location_sensor_options(sensors) do
    [{"None", ""}] ++ Enum.map(sensors, fn s -> {s.name, s.id} end)
  end
end
