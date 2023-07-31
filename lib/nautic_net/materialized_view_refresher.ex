defmodule NauticNet.MaterializedViewRefresher do
  @moduledoc """
  GenServer to refresh a materialized view at a scheduled interval.

  ## Options

    - `:view` (required) - the name of the materialized view
    - `:interval` (required) - the refresh interval, in milliseconds

  """
  use GenServer

  alias NauticNet.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    view = opts[:view] || raise "the :view option is required"
    interval = opts[:interval] || raise "the :interval option is required"

    send(self(), :refresh)
    {:ok, %{view: view, interval: interval}}
  end

  @impl GenServer
  def handle_info(:refresh, state) do
    Ecto.Adapters.SQL.query(Repo, "REFRESH MATERIALIZED VIEW #{state.view};")

    Process.send_after(self(), :refresh, state.interval)

    {:noreply, state}
  end
end
