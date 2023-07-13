alias NauticNet.Racing

{:ok, _race} =
  Racing.create_race(%{
    name: "The DockYard Cup",
    starts_at: DateTime.utc_now(),
    ends_at: DateTime.utc_now() |> DateTime.add(3600),
    # Note this coordinate is ordered in PostGIS as {longitude, latitude}
    center: %Geo.Point{coordinates: {-70.9173206, 42.2823685}}
  })

{:ok, _boat} = Racing.create_boat(%{name: "Edmund Fitzgerald", identifier: "GRDN", serial: "000"})
{:ok, _boat} = Racing.create_boat(%{name: "R.M.S. Titanic", identifier: "SOS", serial: "001"})
