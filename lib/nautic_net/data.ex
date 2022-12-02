defmodule NauticNet.Data do
  @moduledoc """
  Sensor data CRUD.
  """
  import Ecto.Query

  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.PositionSample
  alias NauticNet.Data.Sensor
  alias NauticNet.Protobuf
  alias NauticNet.Racing.Boat
  alias NauticNet.Repo
  alias NauticNet.Util

  ### DataPoints

  # Inserts all the DataPoints from a DataSet protobuf
  def insert_data_points!(%Boat{} = boat, %Protobuf.DataSet{} = data_set) do
    sensor_id_lookup = create_missing_sensors(boat, data_set)

    Enum.map(data_set.data_points, fn %Protobuf.DataSet.DataPoint{} = data_point ->
      insert_data_point!(boat, data_point, sensor_id_lookup)
    end)
  end

  # Inerts a single DataPoint with the appropriate sample type
  defp insert_data_point!(boat, data_point, sensor_id_lookup) do
    sample = build_db_sample(data_point.sample)

    sensor_id =
      Map.fetch!(sensor_id_lookup, encode_sensor_identifier(data_point.hw_unique_number))

    params = %{
      boat_id: boat.id,
      sensor_id: sensor_id,
      timestamp: Util.protobuf_timestamp_to_datetime(data_point.timestamp)
    }

    %DataPoint{}
    |> DataPoint.insert_changeset(sample, params)
    |> Repo.insert!()
  end

  # Converts a protobuf sample a DB sample that is ready for insertion
  def build_db_sample({:position, %Protobuf.PositionSample{} = sample}) do
    %PositionSample{point: %Geo.Point{coordinates: {sample.latitude, sample.longitude}}}
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

  # Creates a new Sensor that we haven't yet seen before
  defp create_sensor!(%Boat{} = boat, params) do
    %Sensor{boat_id: boat.id}
    |> Sensor.insert_changeset(params)
    |> Repo.insert!()
  end
end
