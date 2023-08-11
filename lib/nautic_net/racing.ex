defmodule NauticNet.Racing do
  @moduledoc """
  Core model CRUD.
  """
  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor
  alias NauticNet.Racing.Boat
  alias NauticNet.Racing.Race
  alias NauticNet.Repo

  import Ecto.Changeset
  import Ecto.Query

  ### Races

  def create_race(params) do
    %Race{}
    |> Race.changeset(params)
    |> Repo.insert()
  end

  ### Boats

  defmodule BoatStats do
    @moduledoc """
    Represents a row of data for presentation on /boats page.
    """
    @derive {Phoenix.Param, key: :boat_id}
    defstruct [:boat_id, :boat, :sample_count, :sensor_count, :recent_sample_count]
  end

  def get_or_create_boat_by_identifier(identifier, preloads \\ []) do
    case Repo.get_by(Boat, identifier: identifier) do
      nil ->
        {:ok, boat} = create_boat(%{name: identifier, identifier: identifier, serial: "UNKNOWN"})

        boat

      %Boat{} = boat ->
        boat
    end
    |> Repo.preload(preloads)
  end

  def create_boat(params) do
    %Boat{}
    |> Boat.changeset(params)
    |> Repo.insert()
  end

  def flag_boat_as_alive(boat) do
    boat
    |> change(alive_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update!()
  end

  def list_boats_stats do
    boats =
      from(b in Boat,
        order_by: [b.name, b.identifier, b.id]
      )
      |> Repo.all()

    # Total number of samples (per boat)
    sample_counts =
      from(s in Sample,
        select: {s.boat_id, count(s.time)},
        group_by: s.boat_id
      )
      |> Repo.all()
      |> Map.new()

    # Number of samples within the past 60 seconds (per boat)
    recent_sample_counts =
      from(s in Sample,
        select: {s.boat_id, count(s.time)},
        group_by: s.boat_id,
        where: s.time > ^DateTime.add(DateTime.utc_now(), -60)
      )
      |> Repo.all()
      |> Map.new()

    # Total number of sensors (per boat)
    sensor_counts =
      from(s in Sensor,
        select: {s.boat_id, count(s.id)},
        group_by: s.boat_id
      )
      |> Repo.all()
      |> Map.new()

    for boat <- boats do
      %BoatStats{
        boat_id: boat.id,
        boat: boat,
        sample_count: Map.get(sample_counts, boat.id, 0),
        sensor_count: Map.get(sensor_counts, boat.id, 0),
        recent_sample_count: Map.get(recent_sample_counts, boat.id, 0)
      }
    end
  end

  def get_boat!(id) do
    Repo.get!(Boat, id)
  end

  def change_boat(boat, params \\ %{}) do
    Boat.user_changeset(boat, params)
  end

  def update_boat(boat, params \\ %{}) do
    boat
    |> Boat.user_changeset(params)
    |> Repo.update()
  end

  @doc """
  Returns a list of all boat sensors that have provided position samples.
  """
  def list_location_sensors(boat) do
    sensor_ids =
      Sample
      |> where([s], s.boat_id == ^boat.id and s.type == :position)
      |> distinct([s], s.sensor_id)
      |> select([s], s.sensor_id)
      |> Repo.all()

    Sensor
    |> where([s], s.id in ^sensor_ids)
    |> Repo.all()
  end
end
