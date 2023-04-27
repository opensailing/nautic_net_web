defmodule NauticNet.Ingest.UDPServer do
  @moduledoc """
  Listens for DataSet protobuf packets to persist to the database.
  """

  use GenServer

  require Logger

  alias NauticNet.Ingest

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    port = opts[:port] || raise "the :port option is required"

    {:ok, socket} = :gen_udp.open(port, mode: :binary, active: true)

    Logger.debug("Opened UDP port #{port}")

    {:ok,
     %{
       socket: socket
     }}
  end

  @impl true
  def handle_info({:udp, _socket, _address, _port, data}, state) do
    # TODO: Kick this out to another process? Flow? GenStage? Something??
    case Ingest.insert_samples(data) do
      :ok ->
        :ok

      {:error, error} ->
        Logger.error("[UDPServer] Could not decode #{byte_size(data)} bytes: #{inspect(error)}")
    end

    {:noreply, state}
  rescue
    _ ->
      Logger.error("[UDPServer] Error decoding #{byte_size(data)} bytes")
      {:noreply, state}
  end
end
