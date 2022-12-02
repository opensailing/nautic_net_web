defmodule NauticNet.Racing do
  alias NauticNet.Racing.Boat
  alias NauticNet.Racing.Race
  alias NauticNet.Repo

  def upsert_race(race, params) do
    race
    |> Race.changeset(params)
    |> Repo.insert_or_update()
  end

  def upsert_boat(boat, params) do
    boat
    |> Boat.changeset(params)
    |> Repo.insert_or_update()
  end
end
