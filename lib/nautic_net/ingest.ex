defmodule NauticNet.Ingest do
  @moduledoc """
  Takes in sensor protobuf data and persists it to the database.
  """
  import Ecto.Query

  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor
  alias NauticNet.Protobuf
  alias NauticNet.Protobuf.DataSet
  alias NauticNet.Racing
  alias NauticNet.Racing.Boat
  alias NauticNet.Repo
  alias NauticNet.Util

  ### DataPoints

  # Inserts all the DataPoints from an encoded DataSet protobuf
  def insert_samples!(encoded_data_set) when is_binary(encoded_data_set) do
    # This will raise if there is an error
    data_set = DataSet.decode(encoded_data_set)

    # TODO: Handle TrackerSample as a special case
    # %NauticNet.Protobuf.DataSet{
    #   counter: 0,
    #   data_points: [
    #     %NauticNet.Protobuf.DataSet.DataPoint{
    #       timestamp: %Google.Protobuf.Timestamp{
    #         seconds: 1682024372,
    #         nanos: 0,
    #         __unknown_fields__: []
    #       },
    #       hw_unique_number: 0,
    #       sample: {:tracker,
    #        %NauticNet.Protobuf.TrackerSample{
    #          rssi: -24,
    #          rover_data: %NauticNet.Protobuf.RoverData{
    #            latitude: 41.863887786865234,
    #            longitude: -72.12764739990234,
    #            heading: 0,
    #            heel: 242,
    #            cog: 2360,
    #            sog: 1,
    #            battery: 0,
    #            __unknown_fields__: []
    #          },
    #          __unknown_fields__: []
    #        }},
    #       __unknown_fields__: []
    #     }
    #   ],
    #   ref: "",
    #   boat_identifier: "F515BC55",
    #   __unknown_fields__: []
    # }

    # Find the boat
    boat = Racing.get_or_create_boat_by_identifier(data_set.boat_identifier)

    # Create missing sensor rows and store a LUT in memory for quick access
    sensor_id_lookup = create_missing_sensors(boat, data_set)

    sample_rows =
      Enum.flat_map(data_set.data_points, fn protobuf_data_point ->
        # Figure out the sensor DB id
        sensor_id = lookup_sensor(sensor_id_lookup, protobuf_data_point.hw_unique_number)

        # Build the attrs for the DataPoint and associated sample rows
        sample_attr_rows(protobuf_data_point, boat.id, sensor_id)
      end)

    # Do bulk insert – might need to chunk up items if the individual inserts get too big!
    Repo.insert_all(Sample, sample_rows)
  end

  # Inerts a single DataPoint with the appropriate sample type
  defp sample_attr_rows(protobuf_data_point, boat_id, sensor_id) do
    with {:ok, sample_attrs} <- Sample.attrs_from_protobuf_sample(protobuf_data_point.sample) do
      [
        Map.merge(sample_attrs, %{
          boat_id: boat_id,
          sensor_id: sensor_id,
          time: Util.protobuf_timestamp_to_datetime(protobuf_data_point.timestamp)
        })
      ]
    else
      _ -> []
    end
  end

  ### Sensors

  # Converts an int to an uppercase hexadecimal string
  defp encode_sensor_identifier(int) when is_integer(int) do
    int |> Integer.to_string(16) |> String.upcase()
  end

  # Creates any new Sensors that we haven't seen yet. Returns a map of %{hardware_identifier => id} for quick lookup
  defp create_missing_sensors(%Boat{} = boat, %Protobuf.DataSet{} = data_set) do
    # Find all HW identifiers in this DataSet
    sensor_identifiers =
      data_set.data_points
      |> Enum.map(&encode_sensor_identifier(&1.hw_unique_number))
      |> Enum.uniq()

    # Fetch all known Sensors from the DB
    known_sensor_ids_by_identifier =
      Sensor
      |> where([s], s.boat_id == ^boat.id and s.hardware_identifier in ^sensor_identifiers)
      |> select([s], {s.hardware_identifier, s.id})
      |> Repo.all()
      |> Map.new()

    # Create any missing Sensors (only occurs the first time a Sensor shows up)
    Map.new(sensor_identifiers, fn identifier ->
      case Map.fetch(known_sensor_ids_by_identifier, identifier) do
        {:ok, sensor_id} ->
          {identifier, sensor_id}

        :error ->
          sensor = create_sensor!(boat, %{name: identifier, hardware_identifier: identifier})
          {identifier, sensor.id}
      end
    end)
  end

  defp lookup_sensor(sensor_id_lookup, hw_unique_number) when is_integer(hw_unique_number) do
    Map.fetch!(sensor_id_lookup, encode_sensor_identifier(hw_unique_number))
  end

  # Creates a new Sensor that we haven't yet seen before
  defp create_sensor!(%Boat{} = boat, params) do
    %Sensor{boat_id: boat.id}
    |> Sensor.insert_changeset(params)
    |> Repo.insert!()
  end
end
