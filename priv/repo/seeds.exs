alias NauticNet.Racing

{:ok, _race} =
  Racing.create_race(%{
    name: "The DockYard Cup",
    starts_at: DateTime.utc_now(),
    ends_at: DateTime.utc_now() |> DateTime.add(3600),
    center: %Geo.Point{coordinates: {42.2823685, -70.9173206}}
  })

{:ok, _boat} = Racing.create_boat(%{name: "Edmund Fitzgerald", identifier: "GRDN"})
{:ok, _boat} = Racing.create_boat(%{name: "R.M.S. Titanic", identifier: "SOS"})
