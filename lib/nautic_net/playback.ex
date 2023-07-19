defmodule NauticNet.Playback do
  @moduledoc """
  Fetch sample data for display.
  """

  import Ecto.Query

  alias NauticNet.Data.Sample
  alias NauticNet.Playback.Channel
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
    |> case do
      # Always return a nonempty list
      [] -> [Date.utc_today()]
      dates -> dates
    end
  end

  def list_channels_on(%Date{} = date, timezone) do
    Sample
    |> where_date(date, timezone)
    |> join(:left, [sa], b in assoc(sa, :boat))
    |> join(:left, [sa, b], sn in assoc(sa, :sensor))
    |> select([sa, b, sn], %{boat: b, sensor: sn, type: sa.type})
    |> distinct(true)
    |> Repo.all()
    |> Enum.map(fn %{boat: boat, sensor: sensor, type: type} ->
      Channel.new(boat, sensor, type)
    end)
  end

  @doc """
  Returns a list of Boat structs that were active on a given day.
  """
  def list_active_boats(%Date{} = date, timezone) do
    boat_ids =
      Sample
      |> where_date(date, timezone)
      |> select([s], s.boat_id)
      |> distinct(true)
      |> Repo.all()

    Boat
    |> where([b], b.id in ^boat_ids)
    |> order_by([b], b.name)
    |> Repo.all()
  end

  @doc """
  Returns a list of coordinate maps for display in MapLive.

  Keys: :time, :latitude, :longitude, :true_heading
  """
  def list_coordinates(%Channel{} = channel, date_or_interval, timezone) do
    positions =
      Sample
      |> where_channel(channel)
      |> where_date(date_or_interval, timezone)
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

    # TODO: Fetch :true_heading samples on the same date
    headings = []

    merged_coordinates =
      collate_closest_samples(positions, headings, fn
        position, nil ->
          # Need to specify some value...
          Map.put(position, :true_heading, 0)

        position, heading ->
          Map.put(position, :true_heading, heading.angle_rad * 180 / :math.pi())
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
         [ms1, ms2 | ms_rest] = merge_samples,
         merger,
         acc
       ) do
    cond do
      # ms1 is the latest sample before sample, so use it to merge
      DateTime.compare(ms1.time, sample.time) in [:lt, :eq] and
          DateTime.compare(ms2.time, sample.time) == :gt ->
        merged = merger.(sample, ms1)
        collate_closest_samples(rest, merge_samples, merger, [merged | acc])

      # ms1 and ms2 are BOTH before sample, so pop ms1 off the queue
      # DateTime.compare(ms1.time, sample.time) == :lt and
      #     DateTime.compare(ms2.time, sample.time) in [:lt, :eq] ->
      #   collate_closest_samples(samples, [ms2 | ms_rest], merger, acc)

      :else ->
        collate_closest_samples(samples, [ms2 | ms_rest], merger, acc)
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

  # Convert the date to a pair of DateTimes that represent the start and end of the day in the desired
  # timezone, but then convert to UTC for easy interpolation into the database
  defp where_date(query, {start_utc, end_utc}, "Etc/UTC") do
    where(query, [s], s.time >= ^start_utc and s.time <= ^end_utc)
  end

  defp where_date(query, %Date{} = date, timezone) do
    start_utc =
      date
      |> Timex.to_datetime(timezone)
      |> Timex.beginning_of_day()
      |> Timex.to_datetime("Etc/UTC")

    end_utc =
      date
      |> Timex.to_datetime(timezone)
      |> Timex.end_of_day()
      |> Timex.to_datetime("Etc/UTC")

    where_date(query, {start_utc, end_utc}, "Etc/UTC")
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
  def get_sample_range_on(%Date{} = date, timezone) do
    first_sample_at_utc =
      Sample
      |> where_date(date, timezone)
      |> order_by([s], asc: s.time)
      |> limit(1)
      |> select([s], s.time)
      |> Repo.one()

    last_sample_at_utc =
      Sample
      |> where_date(date, timezone)
      |> order_by([s], desc: s.time)
      |> limit(1)
      |> select([s], s.time)
      |> Repo.one()

    if first_sample_at_utc && last_sample_at_utc do
      # Convert from UTC to local
      {
        Timex.to_datetime(first_sample_at_utc, timezone),
        Timex.to_datetime(last_sample_at_utc, timezone)
      }
    else
      # Generate local start/end of day if there are no samples
      {
        date |> Timex.to_datetime(timezone) |> Timex.beginning_of_day(),
        date |> Timex.to_datetime(timezone) |> Timex.end_of_day()
      }
    end
  end
end
