defmodule NauticNet.Playback do
  @moduledoc """
  Fetch sample data for display.
  """

  import Ecto.Query

  alias NauticNet.Data.ActiveChannel
  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor
  alias NauticNet.LocalDate
  alias NauticNet.Playback.Channel
  alias NauticNet.Racing.Boat
  alias NauticNet.Repo

  def list_channels_on(%LocalDate{} = local_date) do
    boats_by_id = Boat |> Repo.all() |> Map.new(&{&1.id, &1})
    sensors_by_id = Sensor |> Repo.all() |> Map.new(&{&1.id, &1})

    ActiveChannel
    |> where([as], as.utc_date in ^LocalDate.utc_dates(local_date))
    |> select([s], [:boat_id, :sensor_id, :type])
    |> distinct(true)
    |> Repo.all()
    |> Enum.map(fn s ->
      boat = boats_by_id[s.boat_id]
      sensor = sensors_by_id[s.sensor_id]

      Channel.new(boat, sensor, s.type)
    end)
  end

  @doc """
  Returns a list of Boat structs that were active on a given day.
  """
  def list_active_boats(%LocalDate{} = local_date) do
    boat_ids =
      Sample
      |> where_local_date(local_date)
      |> select([s], s.boat_id)
      |> distinct(true)
      |> Repo.all()

    Boat
    |> where([b], b.id in ^boat_ids)
    |> order_by([b], b.name)
    |> Repo.all()
  end

  def list_coordinates(%Channel{} = channel, %LocalDate{} = local_date) do
    list_coordinates(channel, local_date.date, local_date.timezone)
  end

  @doc """
  Returns a list of coordinate maps for display in MapLive.

  Keys: :time, :latitude, :longitude, :magnetic_heading
  """
  def list_coordinates(%Channel{} = channel, local_date_or_interval, local_timezone) do
    positions =
      Sample
      |> where_channel(channel)
      |> where_local_date(local_date_or_interval, local_timezone)
      |> order_by([s], s.time)
      |> select([s], {s.time, s.position})
      |> Repo.all()
      # Note: The ordering of PostGIS ordinates is the opposite of what you expect!
      |> Enum.map(fn {utc_datetime, %Geo.Point{coordinates: {lon, lat}}} ->
        %{
          time: utc_datetime,
          latitude: lat,
          longitude: lon
        }
      end)

    headings =
      Sample
      |> where(boat_id: ^channel.boat.id)
      |> where(type: :magnetic_heading)
      |> where_local_date(local_date_or_interval, local_timezone)
      |> order_by([s], s.time)
      |> select([s], {s.time, s.angle})
      |> Repo.all()
      |> Enum.map(fn {utc_datetime, angle} ->
        %{time: utc_datetime, angle: angle * 180 / :math.pi()}
      end)

    merged_coordinates =
      collate_closest_samples(positions, headings, fn
        position, nil ->
          # Need to specify some value...
          Map.put(position, :magnetic_heading, 0)

        position, heading ->
          Map.put(position, :magnetic_heading, heading.angle)
      end)

    merged_coordinates
  end

  # TODO: IDK why Dialyzer is angry, but I don't have time to figure it out. Maybe you do.
  @dialyzer {:nowarn_function, collate_closest_samples: 4}

  # For every sample, look for the closest merge sample that has occurred BEFORE the main sample.
  # Then, call the merger function to combine them. The resulting list of merged samples will be
  # the same length as the input samples. Each list of samples must have a :time field, and be
  # already ordered ascending by that time.
  defp collate_closest_samples(samples, merge_samples, merger, acc \\ [])

  # Base case - we're done!
  defp collate_closest_samples([], _, _, acc), do: Enum.reverse(acc)

  # No more merge samples remaining - pass `nil` argument to merger function
  defp collate_closest_samples([sample | rest], [], merger, acc) do
    merged = merger.(sample, nil)
    collate_closest_samples(rest, [], merger, [merged | acc])
  end

  defp collate_closest_samples([sample | rest], [merge_sample], merger, acc) do
    if DateTime.compare(merge_sample.time, sample.time) in [:lt, :eq] do
      # Only use merge_sample if it's in the past
      merged = merger.(sample, merge_sample)
      collate_closest_samples(rest, [merge_sample], merger, [merged | acc])
    else
      # No more merge samples remaining :(
      collate_closest_samples(rest, [], merger, acc)
    end
  end

  defp collate_closest_samples(
         [sample | rest] = samples,
         [ms | ms_rest] = merge_samples,
         merger,
         acc
       ) do
    cond do
      # merge sample is the latest sample before sample and is inside time window
      DateTime.compare(ms.time, sample.time) in [:lt, :eq] and
          abs(DateTime.diff(ms.time, sample.time)) <= 1 ->
        merged = merger.(sample, ms)
        collate_closest_samples(rest, ms_rest, merger, [merged | acc])

      # merge sample is happening later, so let's try it with the next position
      DateTime.compare(ms.time, sample.time) == :gt ->
        merged = merger.(sample, nil)
        collate_closest_samples(rest, merge_samples, merger, [merged | acc])

      :else ->
        merged = merger.(sample, nil)
        collate_closest_samples(samples, ms_rest, merger, [merged | acc])
    end
  end

  @doc """
  Given a list of %Signal{} structs, populates each :latest_sample at a given time.

  Samples up to 5 seconds in the past are considered "latest".
  """
  def fill_latest_samples(signals, end_datetime) do
    start_datetime = DateTime.add(end_datetime, -5, :second)

    # Bulk fetch latest samples from all channels at once
    channel_samples =
      signals
      |> Enum.map(& &1.channel)
      |> list_latest_samples_by_channel(start_datetime, end_datetime)

    # Use lookup table
    for signal <- signals do
      %{signal | latest_sample: channel_samples[signal.channel]}
    end
  end

  # Returns a map of %{%Channel{} => %Sample{}} of the latest sample within the given interval
  defp list_latest_samples_by_channel(
         channels,
         %DateTime{} = start_datetime,
         %DateTime{} = end_datetime
       ) do
    samples =
      Sample
      # This is slow so I am commenting it out for now, but it might be desired later
      # |> where(^in_channels(channels))
      |> where([s], s.time <= ^end_datetime and s.time > ^start_datetime)
      |> order_by([s], desc: s.time)
      |> Repo.all()

    Map.new(channels, fn channel ->
      sample =
        Enum.find(
          samples,
          fn sample ->
            sample.boat_id == channel.boat.id and
              sample.sensor_id == channel.sensor.id and
              sample.type == channel.type
          end
        )

      {channel, sample}
    end)
  end

  # Returns a dynamic expression that can be used in WHERE clauses to filter by multiple channels
  # defp in_channels(channels) do
  #   Enum.reduce(channels, dynamic(true), fn channel, dynamic ->
  #     dynamic(
  #       [s],
  #       ^dynamic or
  #         (s.boat_id == ^channel.boat.id and
  #            s.sensor_id == ^channel.sensor.id and
  #            s.type == ^channel.type)
  #     )
  #   end)
  # end

  defp where_local_date(query, %LocalDate{} = local_date) do
    where_utc_date(query, local_date)
  end

  defp where_local_date(query, %Date{} = date, timezone) do
    where_utc_date(query, %LocalDate{date: date, timezone: timezone})
  end

  defp where_utc_date(query, %LocalDate{} = local_date) do
    {start_utc, end_utc} = LocalDate.utc_interval(local_date)
    where(query, [s], s.time >= ^start_utc and s.time <= ^end_utc)
  end

  defp where_channel(sample_query, %Channel{} = channel) do
    sample_query
    |> where([s], s.boat_id == ^channel.boat.id)
    |> where([s], s.sensor_id == ^channel.sensor.id)
    |> where([s], s.type == ^channel.type)
  end

  @doc """
  Returns the range of DateTimes over which samples exist on a given date.
  """
  def get_sample_range_on(%LocalDate{} = local_date) do
    first_sample_at_utc =
      Sample
      |> where_local_date(local_date)
      |> order_by([s], asc: s.time)
      |> limit(1)
      |> select([s], s.time)
      |> Repo.one()

    last_sample_at_utc =
      Sample
      |> where_local_date(local_date)
      |> order_by([s], desc: s.time)
      |> limit(1)
      |> select([s], s.time)
      |> Repo.one()

    if first_sample_at_utc && last_sample_at_utc do
      # Convert from UTC to local
      {
        Timex.to_datetime(first_sample_at_utc, local_date.timezone),
        Timex.to_datetime(last_sample_at_utc, local_date.timezone)
      }
    else
      # Generate local start/end of day if there are no samples
      LocalDate.local_interval(local_date)
    end
  end
end
