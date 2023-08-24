defmodule NauticNetWeb.Api.DataSetControllerTest do
  use NauticNetWeb.ConnCase

  alias NauticNet.Protobuf
  alias NauticNet.Protobuf.DataSet
  alias NauticNet.Racing
  alias NauticNet.Util

  describe "create/2" do
    test "successfully inserts a position sample", %{conn: conn} do
      # GIVEN
      now = DateTime.utc_now()

      data_set =
        DataSet.new!(
          counter: 0,
          ref: "some ref",
          boat_identifier: "BOAT",
          data_points: [
            DataSet.DataPoint.new!(
              timestamp: Util.datetime_to_protobuf_timestamp(now),
              hw_id: 123,
              sample:
                {:position,
                 Protobuf.PositionSample.new!(
                   latitude: 40.0,
                   longitude: -70.0
                 )}
            )
          ]
        )

      base64 = data_set |> DataSet.encode() |> Base.encode64()

      params = %{
        "proto_base64" => base64
      }

      # WHEN
      conn = post(conn, ~p"/api/data_sets", params)

      # THEN
      assert text_response(conn, 201) == ""

      boat = Racing.get_or_create_boat_by_identifier("BOAT", sensors: [:samples])
      assert alive_at = %DateTime{} = boat.alive_at
      assert DateTime.compare(DateTime.add(DateTime.utc_now(), -5), alive_at) == :lt

      assert [sensor] = boat.sensors
      assert sensor.hardware_identifier == "7B"

      assert [sample] = sensor.samples
      assert sample.time == now
      assert sample.type == :position
      assert sample.position.coordinates == {-70.0, 40.0}
    end
  end
end
