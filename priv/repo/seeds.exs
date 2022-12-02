alias NauticNet.Racing
alias NauticNet.Racing.Boat
alias NauticNet.Racing.Race

{:ok, _race} =
  Racing.upsert_race(%Race{}, %{
    name: "The DockYard Cup",
    starts_at: DateTime.utc_now(),
    ends_at: DateTime.utc_now() |> DateTime.add(3600),
    center: %Geo.Point{coordinates: {42.2823685, -70.9173206}}
  })

{:ok, _boat} = Racing.upsert_boat(%Boat{}, %{name: "Edmund Fitzgerald"})
{:ok, _boat} = Racing.upsert_boat(%Boat{}, %{name: "R.M.S. Titanic"})
