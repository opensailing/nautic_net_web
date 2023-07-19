defmodule NauticNet.Seeds do
  alias NauticNet.Racing

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
end
