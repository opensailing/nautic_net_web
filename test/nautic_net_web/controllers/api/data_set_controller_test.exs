defmodule NauticNetWeb.Api.DataSetControllerTest do
  use NauticNetWeb.ConnCase

  alias NauticNet.Protobuf
  alias NauticNet.Racing
  alias NauticNet.Util

  describe "create/2" do
    test "successfully inserts a position sample", %{conn: conn} do
      # GIVEN
      now = DateTime.utc_now()

      data_set =
        Protobuf.DataSet.new!(
          counter: 0,
          ref: "some ref",
          data_points: [
            Protobuf.DataSet.DataPoint.new!(
              timestamp: Util.datetime_to_protobuf_timestamp(now),
              hw_unique_number: 123,
              sample:
                {:position,
                 Protobuf.PositionSample.new!(
                   latitude: 40.0,
                   longitude: -70.0
                 )}
            )
          ]
        )

      base64 = data_set |> Protobuf.DataSet.encode() |> Base.encode64()

      params = %{
        "boat_identifier" => "BOAT",
        "proto_base64" => base64
      }

      # WHEN
      conn = post(conn, ~p"/api/data_sets", params)

      # THEN
      assert text_response(conn, 201) == ""

      boat = Racing.get_or_create_boat_by_identifier("BOAT", sensors: [:data_points])

      assert [sensor] = boat.sensors
      assert sensor.hardware_identifier == "7B"

      assert [data_point] = sensor.data_points
      assert data_point.timestamp == now
      assert data_point.type == :position
    end
  end
end
