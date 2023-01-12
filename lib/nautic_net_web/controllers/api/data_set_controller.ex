defmodule NauticNetWeb.API.DataSetController do
  use NauticNetWeb, :controller

  alias NauticNet.DataIngest
  alias NauticNet.Protobuf.DataSet
  alias NauticNet.Racing

  def create(conn, %{"proto_base64" => proto_base64}) do
    data_set =
      case Base.decode64(proto_base64) do
        {:ok, binary} -> DataSet.decode(binary)
        :error -> raise "oh no"
      end

    boat = Racing.get_or_create_boat_by_identifier(data_set.boat_identifier)

    DataIngest.insert_samples!(boat, data_set)

    conn
    |> put_status(:created)
    |> text("")
  end
end
