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

    udp_opts = udp_opts()
    {:ok, socket} = :gen_udp.open(port, udp_opts())

    if ip = udp_opts[:ip] do
      Logger.info("Bound to UDP address #{:inet.ntoa(ip)}:#{port}")
    else
      Logger.info("Bound to UDP port #{port}")
    end

    {:ok,
     %{
       socket: socket
     }}
  end

  defp udp_opts do
    base_opts = [mode: :binary, active: true]

    #
    # This is necessary to bind to the "fly-global-services" address on Fly.io
    # https://fly.io/docs/app-guides/udp-and-tcp/#the-fly-global-services-address
    #
    with {:ok, hostname} <- System.fetch_env("UDP_HOSTNAME"),
         hostname = to_charlist(hostname),
         {:ok, ip} <- :inet.getaddr(hostname, :inet) do
      base_opts ++ [ip: ip]
    else
      _ ->
        base_opts
    end
  end

  @impl true
  def handle_info({:udp, _socket, address, _port, data}, state) do
    Logger.info("[UDPServer] [#{:inet.ntoa(address)}] - Received #{byte_size(data)} bytes")

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
