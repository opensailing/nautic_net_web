defmodule NauticNet.Playback do
  @moduledoc """
  Fetch sample data for display.
  """

  defmodule DataSource do
    defstruct [:id, :name, :measurement, :reference, :selected_sensor, sensors: []]
  end

  import Ecto.Query

  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor
  alias NauticNet.Racing.Boat
  alias NauticNet.Repo

  @doc """
  Returns an ordered list of all dates with any data samples.

  TODO: This query is slow; let's improve the performance somehow.
  """
  def list_all_dates(timezone) do
    Sample
    |> select([s], fragment("(? at time zone ?)::date", s.time, ^timezone))
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort(Date)
    |> case do
      # Always return a nonempty list
      [] -> [Date.utc_today()]
      dates -> dates
    end
  end

  @doc """
  Returns a list of Boat structs that were active on a given day.
  """
  def list_active_boats(%Date{} = date, timezone) do
    boat_ids =
      Sample
      |> where([s], fragment("(? at time zone ?)::date", s.time, ^timezone) == ^date)
      |> select([s], s.boat_id)
      |> distinct(true)
      |> Repo.all()

    Boat
    |> where([b], b.id in ^boat_ids)
    |> order_by([b], b.name)
    |> Repo.all()
  end

  @doc """
  Returns an ordered list of DataSource structs that represent the different type of
  measurements that can be displayed directly from the sample data.
  """
  def all_data_sources do
    [
      %DataSource{
        id: "position",
        name: "Position",
        measurement: :position,
        reference: nil
      },
      %DataSource{
        id: "true_heading",
        name: "Heading (True)",
        measurement: :heading,
        # TODO: Populate the heading reference on the device
        # TODO: If heading data is only magnetic, we need to convert from °M to °T using an API or other data source
        #       to determine magnetic declination
        reference: :none
      },
      %DataSource{
        id: "speed_through_water",
        name: "Speed Through Water",
        measurement: :speed,
        reference: :water
      },
      %DataSource{
        id: "velocity_over_ground",
        name: "SOG & COG",
        measurement: :velocity,
        reference: :true_north
      },
      %DataSource{
        id: "apparent_wind",
        name: "Apparent Wind",
        measurement: :wind_velocity,
        reference: :apparent
      },
      %DataSource{
        id: "true_wind",
        name: "True Wind",
        measurement: :velocity,
        # Unclear if this should be true_north_boat or true_north_water - we don't have any data
        # for this yet to determine it.
        reference: :true_north_boat
      },
      %DataSource{
        id: "depth",
        name: "Depth",
        measurement: :water_depth,
        reference: nil
      }
    ]
  end

  @doc """
  Returns a list of DataSource structs with the available sensors populated.

      [%DataSource{sensors: [...], selected_sensor: %Sensor{} | nil, ...}, ...]

  """
  def list_data_sources(boat, %Date{} = date, timezone) do
    # [%{measurement: :foo, reference: :bar, sensor_id: "bat"}, ...]
    known_sensor_measurements =
      Sample
      |> where([s], fragment("(? at time zone ?)::date", s.time, ^timezone) == ^date)
      |> where([s], s.boat_id == ^boat.id)
      |> select([s], %{measurement: s.measurement, reference: s.reference, sensor_id: s.sensor_id})
      |> distinct(true)
      |> Repo.all()

    # ["sensor_1", "sensor_2", ...]
    known_sensor_ids =
      known_sensor_measurements
      |> Enum.map(& &1.sensor_id)
      |> Enum.uniq()

    # %{"sensor_1" => %Sensor{}, ...}
    sensor_lookup =
      Sensor
      |> where([s], s.id in ^known_sensor_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    # [%DataSource{sensors: [...], selected_sensor: %Sensor{} | nil, ...}, ...]
    for data_source <- all_data_sources() do
      sensors =
        for ksm <- known_sensor_measurements,
            ksm.measurement == data_source.measurement and
              ksm.reference == data_source.reference,
            do: Map.fetch!(sensor_lookup, ksm.sensor_id)

      selected_sensor = List.first(sensors)

      %{data_source | sensors: sensors, selected_sensor: selected_sensor}
    end
  end

  @doc """
  Returns a list of coordinate tuples for display in MapLive.

      [{%NaiveDateTime{}, latitude, longitude}, ...]

  """
  def list_coordinates(%Boat{} = boat, %Date{} = date, timezone, data_sources) do
    position_data_source = fetch_data_source!(data_sources, "position")

    Sample
    |> where_data_source(position_data_source)
    |> where([s], s.boat_id == ^boat.id)
    |> where([s], fragment("(? at time zone ?)::date", s.time, ^timezone) == ^date)
    |> order_by([s], s.time)
    |> select([s], {s.time, s.position})
    |> Repo.all()
    |> Enum.map(fn {time, %Geo.Point{coordinates: {lon, lat}}} ->
      # TODO: Convert `time` to correct timezone (need to add Timex)
      {DateTime.to_naive(time), lat, lon}
    end)
  end

  defp fetch_data_source!(data_sources, data_source_id) do
    data_sources
    |> Enum.find(&(&1.id == data_source_id))
    |> case do
      %DataSource{} = data_source -> data_source
      _ -> raise ArgumentError, "invalid data source id #{inspect(data_source_id)}"
    end
  end

  defp where_data_source(sample_query, %DataSource{selected_sensor: nil}) do
    where(sample_query, false)
  end

  defp where_data_source(sample_query, %DataSource{} = data_source) do
    sample_query
    |> where([s], s.sensor_id == ^data_source.selected_sensor.id)
    |> where([s], s.measurement == ^data_source.measurement)
    |> where_reference(data_source.reference)
  end

  defp where_reference(sample_query, nil), do: where(sample_query, [s], is_nil(s.reference))

  defp where_reference(sample_query, reference),
    do: where(sample_query, [s], s.reference == ^reference)

  # defp get_data_source(id) do
  #   Enum.find(all_data_sources(), &(&1.id == id)) ||
  #     raise "could not find DataSource with id #{inspect(id)}"
  # end

  # defp for_data_source(sample_query, data_source_id) when is_binary(data_source_id) do
  #   for_data_source(sample_query, get_data_source(data_source_id))
  # end

  # defp for_data_source(sample_query, %DataSource{} = hud) do
  #   where(sample_query, [s], s.measurement == ^hud.measurement and s.reference == ^hud.reference)
  # end
end
