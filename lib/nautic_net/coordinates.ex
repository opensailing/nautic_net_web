defmodule NauticNet.Coordinates do
  @default_path "priv/external/"

  def get_coordinates(filename) do
    {:ok, rows} = File.read(@default_path <> filename)

    rows
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.map(
      &(&1
        |> String.split(",")
        |> List.to_tuple()
        |> then(fn {time, latitude, longitude} ->
          {:ok, utc_datetime, 0} = DateTime.from_iso8601(time)
          {utc_datetime, String.to_float(latitude), String.to_float(longitude)}
        end))
    )
  end

  def get_center(coordinates) do
    {min_latitude, max_latitude} =
      coordinates
      |> Enum.map(fn {_, latitude, _} -> latitude end)
      |> Enum.min_max()

    {min_longitude, max_longitude} =
      coordinates
      |> Enum.map(fn {_, _, longitude} -> longitude end)
      |> Enum.min_max()

    {(min_latitude + max_latitude) / 2, (min_longitude + max_longitude) / 2}
  end
end
