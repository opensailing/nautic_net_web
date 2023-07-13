defmodule NauticNetWeb.BoatsLive do
  use NauticNetWeb, :live_view

  alias NauticNet.Racing
  alias NauticNet.Racing.BoatStats

  def mount(_, _, socket) do
    socket = load(socket, :boat_stats)
    Process.send_after(self(), :refresh, :timer.seconds(10))

    {:ok, socket}
  end

  def handle_info(:refresh, socket) do
    socket = load(socket, :boat_stats)
    Process.send_after(self(), :refresh, :timer.seconds(10))

    {:noreply, socket}
  end

  defp load(socket, :boat_stats) do
    assign(socket, boats_stats: Racing.list_boats_stats())
  end

  defp status_label(%{boat_stats: %BoatStats{} = boat_stats} = assigns) do
    online? =
      boat_stats.boat.alive_at != nil and
        DateTime.compare(DateTime.add(boat_stats.boat.alive_at, 60), DateTime.utc_now()) == :gt

    recent_samples? = boat_stats.recent_sample_count > 0

    assigns =
      cond do
        online? and recent_samples? ->
          assign(assigns, text: "Online", class: "bg-green-600")

        online? and not recent_samples? ->
          assign(assigns, text: "Heartbeat", class: "bg-yellow-600")

        not online? ->
          assign(assigns, text: "Offline", class: "bg-gray-400")
      end

    ~H"""
    <span class={[@class, "rounded text-white uppercase text-xs font-semibold px-2 py-0.5"]}>
      <%= @text %>
    </span>
    """
  end
end
