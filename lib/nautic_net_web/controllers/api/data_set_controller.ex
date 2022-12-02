defmodule NauticNetWeb.API.DataSetController do
  use NauticNetWeb, :controller

  alias NauticNet.Data
  alias NauticNet.Protobuf.DataSet
  alias NauticNet.Racing

  def create(
        conn,
        %{
          "boat_identifier" => identifier,
          "proto_base64" => proto_base64
        }
      ) do
    boat = Racing.get_or_create_boat_by_identifier(identifier)

    data_set =
      case Base.decode64(proto_base64) do
        {:ok, binary} -> DataSet.decode(binary)
        :error -> raise "oh no"
      end

    Data.insert_data_points!(boat, data_set)

    conn
    |> put_status(:created)
    |> text("")
  end
end
