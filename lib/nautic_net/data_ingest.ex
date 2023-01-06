defmodule NauticNet.DataIngest do
  @moduledoc """
  Takes in sensor protobuf data and persists it to the database.
  """
  import Ecto.Query

  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.SampleSchema
  alias NauticNet.Data.Sensor
  alias NauticNet.Protobuf
  alias NauticNet.Racing.Boat
  alias NauticNet.Repo
  alias NauticNet.Util

  ### DataPoints

  # Inserts all the DataPoints from a DataSet protobuf
  def insert_data_points!(%Boat{} = boat, %Protobuf.DataSet{} = data_set) do
    sensor_id_lookup = create_missing_sensors(boat, data_set)

    # For insert_all, keep track of all the rows to insert
    initial_rows = %{DataPoint => []}

    data_set.data_points
    |> Enum.reduce(initial_rows, fn protobuf_data_point, rows ->
      # Figure out the sensor DB id
      sensor_id = lookup_sensor(sensor_id_lookup, protobuf_data_point.hw_unique_number)

      # Build the attrs for the DataPoint and associated sample rows
      accumulate_data_point_row(rows, protobuf_data_point, boat.id, sensor_id)
    end)
    |> Enum.map(fn {schema, schema_rows} ->
      # Do bulk inserts per table – might need to chunk up items if the individual inserts get too big!
      Repo.insert_all(schema, schema_rows)
    end)
  end

  # Inerts a single DataPoint with the appropriate sample type
  defp accumulate_data_point_row(rows, protobuf_data_point, boat_id, sensor_id) do
    {protobuf_field, protobuf_sample} = protobuf_data_point.sample

    with {:ok, sample_schema, sample_attrs} <-
           SampleSchema.attrs_from_protobuf_sample(protobuf_sample) do
      data_point_attrs = %{
        boat_id: boat_id,
        measurement: protobuf_field,
        id: Ecto.UUID.generate(),
        sensor_id: sensor_id,
        timestamp: Util.protobuf_timestamp_to_datetime(protobuf_data_point.timestamp),
        type: sample_schema.sample_type()
      }

      sample_attrs = Map.merge(sample_attrs, %{data_point_id: data_point_attrs.id})

      rows
      |> Map.put_new(sample_schema, [])
      |> Map.update!(DataPoint, fn list -> [data_point_attrs | list] end)
      |> Map.update!(sample_schema, fn list -> [sample_attrs | list] end)
    else
      _ -> rows
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
