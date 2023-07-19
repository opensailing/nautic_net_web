defmodule NauticNet.Seeds do
  import Ecto.Query

  alias NauticNet.Racing
  alias NauticNet.Racing.Boat
  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor
  alias NauticNet.Repo

  def run do
    %{}
    |> create_races!()
    |> create_boats!()
  end

  defp create_races!(map) do
    {:ok, race} =
      Racing.create_race(%{
        name: "The DockYard Cup",
        starts_at: DateTime.utc_now(),
        ends_at: DateTime.utc_now() |> DateTime.add(3600),
        # Note this coordinate is ordered in PostGIS as {longitude, latitude}
        center: %Geo.Point{coordinates: {-70.9173206, 42.2823685}}
      })

    Map.put(map, :race, race)
  end

  def create_boats!(map) do
    {:ok, boat1} =
      Racing.create_boat(%{name: "Edmund Fitzgerald", identifier: "GRDN", serial: "000"})

    {:ok, boat2} = Racing.create_boat(%{name: "R.M.S. Titanic", identifier: "SOS", serial: "001"})

    Map.merge(map, %{boat1: boat1, boat2: boat2})
  end

  @dump_fields %{
    boat: [:id, :name, :identifier, :alive_at, :serial, :inserted_at, :updated_at],
    sensor: [:id, :boat_id, :hardware_identifier, :name, :inserted_at, :updated_at],
    sample: [:time, :boat_id, :sensor_id, :type, :magnitude, :angle, :position]
  }

  @doc """
  Saves Boats, Sensors, and Samples on the given UTC dates to tmp/samples.dump.

  The file is in the Erlang term format.

  Restore it using `clean_and_restore_samples/0`.
  """
  def dump_samples(utc_date_or_dates) do
    boats =
      Boat
      |> Repo.all()
      |> Enum.map(&Map.take(&1, @dump_fields.boat))

    sensors =
      Sensor
      |> Repo.all()
      |> Enum.map(&Map.take(&1, @dump_fields.sensor))

    utc_dates = List.wrap(utc_date_or_dates)

    samples =
      Sample
      |> where([s], fragment("date(?)", s.time) in ^utc_dates)
      |> Repo.all()
      |> Enum.map(&Map.take(&1, @dump_fields.sample))

    dump =
      :erlang.term_to_binary(%{
        boats: boats,
        sensors: sensors,
        samples: samples
      })

    File.write!("tmp/samples.dump", dump)

    :ok
  end

  @doc """
  Restores Boats, Sensors, and Samples from tmp/samples.dump.

  All existing boats, sensors, and samples will be deleted.

  Create the dump file from a existing data using `dump_samples/0`.
  """
  def clean_and_restore_samples do
    binary = File.read!("tmp/samples.dump")

    %{
      boats: boats,
      sensors: sensors,
      samples: samples
    } = :erlang.binary_to_term(binary)

    Repo.delete_all(Sample)
    Repo.delete_all(Sensor)
    Repo.delete_all(Boat)

    Repo.insert_all(Boat, boats)
    Repo.insert_all(Sensor, sensors)

    samples
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Sample, chunk)
    end)

    IO.puts("Inserted #{length(samples)} samples for #{length(boats)} boats")

    :ok
  end
end
