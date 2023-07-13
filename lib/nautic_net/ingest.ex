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
  def insert_samples(encoded_data_set) when is_binary(encoded_data_set) do
    encoded_data_set
    |> DataSet.decode()
    |> insert_data_set()
  rescue
    error ->
      {:error, error}
  end

  defp insert_data_set(data_set) do
    # Find the boat
    boat = Racing.get_or_create_boat_by_identifier(data_set.boat_identifier, [])
    boat = Racing.flag_boat_as_alive(boat)

    # Create missing sensor rows and store a LUT in memory for quick access
    sensor_id_lookup = create_missing_sensors(boat, data_set)

    sample_rows =
      Enum.flat_map(data_set.data_points, fn protobuf_data_point ->
        # Figure out the sensor DB id
        sensor_id = lookup_sensor(sensor_id_lookup, protobuf_data_point.hw_id)

        # Build the attrs for the DataPoint and associated sample rows
        sample_attr_rows(protobuf_data_point, boat.id, sensor_id)
      end)

    # Do bulk insert – might need to chunk up items if the individual inserts get too big!
    Repo.insert_all(Sample, sample_rows)

    broadcast_new_samples(boat, sample_rows)

    :ok
  end

  # Inerts one or many DataPoints with the appropriate sample types
  defp sample_attr_rows(protobuf_data_point, boat_id, sensor_id) do
    with {:ok, list_of_sample_attrs} <-
           Sample.attrs_from_protobuf_sample(protobuf_data_point.sample) do
      Enum.map(list_of_sample_attrs, fn attrs ->
        Map.merge(attrs, %{
          boat_id: boat_id,
          sensor_id: sensor_id,
          time: Util.protobuf_timestamp_to_datetime(protobuf_data_point.timestamp)
        })
      end)
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
      |> Enum.map(&encode_sensor_identifier(&1.hw_id))
      |> Enum.uniq()

    # Fetch all known Sensors from the DB
    known_sensor_ids_by_identifier =
      Sensor
      |> where([s], s.boat_id == ^boat.id and s.hardware_identifier in ^sensor_identifiers)
      |> select([s], {s.hardware_identifier, s.id})
      |> Repo.all()
      |> Map.new()

    # Create any missing Sensors (only occurs the first time a Sensor shows up)
    lookup =
      Map.new(sensor_identifiers, fn identifier ->
        case Map.fetch(known_sensor_ids_by_identifier, identifier) do
          {:ok, sensor_id} ->
            {identifier, sensor_id}

          :error ->
            sensor = create_sensor!(boat, %{name: identifier, hardware_identifier: identifier})
            {identifier, sensor.id}
        end
      end)

    # If the DataSet provided sensor metadata, let's update that now
    for network_device <- data_set.network_devices do
      Sensor
      |> where(
        [s],
        s.boat_id == ^boat.id and
          s.hardware_identifier == ^encode_sensor_identifier(network_device.hw_id)
      )
      |> Repo.one()
      |> case do
        nil ->
          create_sensor!(boat, %{
            name: sensor_name(network_device.name),
            hardware_identifier: encode_sensor_identifier(network_device.hw_id)
          })

        %Sensor{} = sensor ->
          update_sensor!(sensor, %{name: sensor_name(network_device.name)})
      end
    end

    lookup
  end

  defp lookup_sensor(sensor_id_lookup, hw_id) when is_integer(hw_id) do
    Map.fetch!(sensor_id_lookup, encode_sensor_identifier(hw_id))
  end

  # Creates a new Sensor that we haven't yet seen before
  defp create_sensor!(%Boat{} = boat, params) do
    %Sensor{boat_id: boat.id}
    |> Sensor.insert_changeset(params)
    |> Repo.insert!()
  end

  # Updates a new Sensor with new metadata
  defp update_sensor!(sensor, params) do
    sensor
    |> Sensor.update_changeset(params)
    |> Repo.update!()
  end

  defp broadcast_new_samples(boat, sample_rows) do
    samples = Enum.map(sample_rows, &struct!(Sample, &1))

    Phoenix.PubSub.broadcast(NauticNet.PubSub, "boat:#{boat.id}", {:new_samples, samples})

    :ok
  end

  defp sensor_name(name) do
    if name |> to_string() |> String.trim() == "", do: "Unknown Device", else: name
  end
end
