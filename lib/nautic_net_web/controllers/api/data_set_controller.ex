defmodule NauticNetWeb.API.DataSetController do
  use NauticNetWeb, :controller

  alias NauticNet.Ingest

  def create(conn, %{"proto_base64" => proto_base64}) do
    case Base.decode64(proto_base64) do
      {:ok, binary} -> Ingest.insert_samples!(binary)
      :error -> raise "oh no"
    end

    conn
    |> put_status(:created)
    |> text("")
  end
end
