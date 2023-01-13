defmodule NauticNet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      NauticNetWeb.Telemetry,
      # Start the Ecto repository
      NauticNet.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: NauticNet.PubSub},
      {BoatVisualizer.NetCDF,
       %{
         dataset_filename: Path.join(:code.priv_dir(:nautic_net), "dataset_20221221.nc"),
         start_date: ~D[2022-12-21],
         end_date: ~D[2022-12-22]
       }},
      # Start Finch
      {Finch, name: NauticNet.Finch},
      # Start the Endpoint (http/https)
      NauticNetWeb.Endpoint,
      # Start the protobuf UDP listener
      {NauticNet.Ingest.UDPServer, port: Application.get_env(:nautic_net, :udp_port, 20002)}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NauticNet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NauticNetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
