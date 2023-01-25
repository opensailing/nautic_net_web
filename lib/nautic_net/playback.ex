defmodule NauticNet.Playback do
  @moduledoc """
  Fetch sample data for display.
  """

  defmodule DataSource do
    defstruct [:id, :name, :measurement, :reference]
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
  Returns a map to enumerate which Sensors are available to satisfy a particular DataSource.

  Returns a map with DataSource id as a key and a list of Sensor structs as values. Example:

      %{
        "position" => [%Sensor{}, %Sensor{}, ...],
        "heading" => [%Sensor{}, ...],
        ...
      }
  """
  def sensors_by_data_source_id(%Date{} = date, timezone, boat) do
    # [%{measurement: :foo, reference: :bar, sensor_id: "bat"}, ...]
    known_sensor_measurements =
      Sample
      |> where([s], fragment("(? at time zone ?)::date", s.time, ^timezone) == ^date)
      |> where([s], s.boat_id == ^boat.id)
      |> select([s], %{measurement: s.measurement, reference: s.reference, sensor_id: s.sensor_id})
      |> distinct(true)
      |> Repo.all()
      |> IO.inspect()

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

    # %{
    #   "position" => [%Sensor{}, %Sensor{}, ...],
    #   "heading" => [%Sensor{}, ...],
    #   ...
    # }
    for data_source <- list_data_sources(), into: %{} do
      sensors =
        for ksm <- known_sensor_measurements,
            ksm.measurement == data_source.measurement and
              ksm.reference == data_source.reference,
            do: Map.fetch!(sensor_lookup, ksm.sensor_id)

      {data_source.id, sensors}
    end
  end

  @doc """
  Returns an ordered list of DataSource structs that represent the different type of
  measurements that can be displayed directly from the sample data.
  """
  def list_data_sources do
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
        #       for magnetic declination
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

  defp get_data_source(id) do
    Enum.find(list_data_sources(), &(&1.id == id)) ||
      raise "could not find DataSource with id #{inspect(id)}"
  end

  defp for_data_source(sample_query, data_source_id) when is_binary(data_source_id) do
    for_data_source(sample_query, get_data_source(data_source_id))
  end

  defp for_data_source(sample_query, %DataSource{} = hud) do
    where(sample_query, [s], s.measurement == ^hud.measurement and s.reference == ^hud.reference)
  end
end
