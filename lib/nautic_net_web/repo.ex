defmodule NauticNet.Repo do
  use Ecto.Repo,
    otp_app: :nautic_net_web,
    adapter: Ecto.Adapters.Postgres
end
