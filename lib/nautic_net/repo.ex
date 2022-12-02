defmodule NauticNet.Repo do
  use Ecto.Repo,
    otp_app: :nautic_net,
    adapter: Ecto.Adapters.Postgres
end
