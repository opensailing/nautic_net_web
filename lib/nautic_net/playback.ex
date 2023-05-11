defmodule NauticNet.Playback do
  @moduledoc """
  Fetch sample data for display.
  """

  import Ecto.Query

  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor
  alias NauticNet.Playback.DataSource
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
      |> where_date(date, timezone)
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
    Enum.map(Sample.types(), fn type ->
      %DataSource{
        id: to_string(type.type),
        name: type.name,
        type: type.type
      }
    end)
  end

  @doc """
  Returns a list of DataSource structs with the available sensors populated.

      [%DataSource{sensors: [...], selected_sensor: %Sensor{} | nil, ...}, ...]

  """
  def list_data_sources(boat, %Date{} = date, timezone) do
    # [%{measurement: :foo, reference: :bar, sensor_id: "bat"}, ...]
    known_sensor_measurements =
      Sample
      |> where([s], s.boat_id == ^boat.id)
      |> where_date(date, timezone)
      |> select([s], %{type: s.type, sensor_id: s.sensor_id})
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
            ksm.type == data_source.type,
            do: Map.fetch!(sensor_lookup, ksm.sensor_id)

      selected_sensor = List.first(sensors)

      %{data_source | sensors: sensors, selected_sensor: selected_sensor}
    end
  end

  @doc """
  Returns a list of coordinate tuples for display in MapLive.

      [{%DateTime{}, latitude, longitude}, ...]

  """
  def list_coordinates(%Boat{} = boat, %Date{} = date, timezone, data_sources) do
    position_data_source = fetch_data_source!(data_sources, "position")

    Sample
    |> where_data_source(position_data_source)
    |> where([s], s.boat_id == ^boat.id)
    |> where_date(date, timezone)
    |> order_by([s], s.time)
    |> select([s], {s.time, s.position})
    |> Repo.all()
    |> Enum.map(fn {utc_datetime, %Geo.Point{coordinates: {lon, lat}}} ->
      {utc_datetime, lat, lon}
    end)
  end

  def fill_latest_samples(boat, datetime, data_sources) do
    Enum.map(data_sources, fn data_source ->
      # TODO: Optimize this, since it calls N queries
      %{data_source | latest_sample: get_latest_sample(boat, datetime, data_source)}
    end)
  end

  def get_latest_sample(%Boat{} = boat, %DateTime{} = datetime, data_source) do
    cutoff_datetime = DateTime.add(datetime, -1, :minute)

    Sample
    |> where_data_source(data_source)
    |> where([s], s.boat_id == ^boat.id)
    |> where([s], s.time < ^datetime and s.time > ^cutoff_datetime)
    |> order_by([s], desc: s.time)
    |> limit(1)
    |> Repo.one()
  end

  # Convert the date to a pair of DateTimes that represent the start and end of the day in the desired
  # timezone, but then convert to UTC for easy interpolation into the database
  defp where_date(query, %Date{} = date, timezone) do
    start_utc =
      date
      |> Timex.to_datetime(timezone)
      |> Timex.beginning_of_day()
      |> Timex.to_datetime("Etc/UTC")

    end_utc =
      date
      |> Timex.to_datetime(timezone)
      |> Timex.end_of_day()
      |> Timex.to_datetime("Etc/UTC")

    where(query, [s], s.time >= ^start_utc and s.time <= ^end_utc)
  end

  def fetch_data_source!(data_sources, data_source_id) do
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
    |> where([s], s.type == ^data_source.type)
  end
end
