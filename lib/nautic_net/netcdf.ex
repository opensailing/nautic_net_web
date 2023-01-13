defmodule BoatVisualizer.NetCDF do
  @moduledoc """
  Loads a dataset in memory.
  """
  use Agent

  import Nx.Defn

  require Logger

  # times are measured in days, so 1 min = 1 / (24 * 60)
  @one_second_in_mjd 1 / (24 * 3600)
  @pi :math.pi()

  def start_link(%{dataset_filename: filename, start_date: start_date, end_date: end_date}) do
    {:ok, file} = NetCDF.File.open(filename)
    Logger.info("Loading NetCDF data")
    file_data = load(file)

    Logger.info("Getting speed and direction tensors")

    start_mjd = Cldr.Calendar.modified_julian_day(start_date)
    end_mjd = Cldr.Calendar.modified_julian_day(end_date)

    {t, speed, direction} =
      abs_and_direction_tensors(
        file_data.u,
        file_data.v,
        Nx.tensor(file_data.t.value),
        start_mjd,
        end_mjd
      )

    {interpolated_time_t, original_indices, p_values} = interpolate_time(t)

    # Logger.info("Interpolation duration #{duration / 1_000_000} seconds")

    lat_t = Nx.tensor(file_data.lat.value)
    lon_t = Nx.tensor(file_data.lon.value)

    Logger.info("Starting NetCDF Agent")

    Agent.start_link(
      fn ->
        %{
          speed: speed,
          direction: direction,
          interpolated_time: interpolated_time_t,
          original_indices: original_indices,
          p_values: p_values,
          epoch: start_mjd,
          lat: lat_t,
          lon: lon_t
        }
      end,
      name: __MODULE__
    )
  end

  @doc """
  Returns data for the requested time index and bounding box.
  """
  def get_geodata(
        time_idx,
        min_lat,
        max_lat,
        min_lon,
        max_lon,
        zoom_level
      ) do
    Agent.get(__MODULE__, fn state ->
      original_idx = state.original_indices[time_idx]

      speed = interpolate(state.speed, original_idx, state.p_values[time_idx])

      direction = interpolate_direction(state.direction, original_idx, state.p_values[time_idx])

      Geodata.GeoData.encode(%Geodata.GeoData{
        currents:
          render_data(
            speed,
            direction,
            state.lat,
            state.lon,
            min_lat,
            min_lon,
            max_lat,
            max_lon,
            zoom_level
          )
      })
    end)
  end

  def get_geodata_time_index(time) do
    Agent.get(__MODULE__, fn state ->
      time_idx =
        state.interpolated_time
        |> Nx.less_equal(time)
        |> Nx.argmax(tie_break: :high)
        |> Nx.to_number()

      time_idx
    end)
  end

  @doc """
  Returns the start time for the file
  """
  def epoch do
    Agent.get(__MODULE__, & &1.epoch)
  end

  defp load(file) do
    # eastward velocity
    {:ok, u_var} = NetCDF.Variable.load(file, "u")
    # northward velocity
    {:ok, v_var} = NetCDF.Variable.load(file, "v")
    # time
    {:ok, t_var} = NetCDF.Variable.load(file, "time")
    # latitude - latc and lonc index the u and v variables
    {:ok, lat_var} = NetCDF.Variable.load(file, "latc")
    # longitude
    {:ok, lon_var} = NetCDF.Variable.load(file, "lonc")

    %{u: u_var, v: v_var, t: t_var, lat: lat_var, lon: lon_var}
  end

  defp abs_and_direction_tensors(u_var, v_var, t, start_mjd, end_mjd) do
    time_size = Nx.size(t)
    shape = {time_size, :auto}

    u = Nx.tensor(u_var.value, type: u_var.type) |> Nx.reshape(shape)
    v = Nx.tensor(v_var.value, type: v_var.type) |> Nx.reshape(shape)
    {speed, direction} = abs_and_direction_tensors_n(u, v)
    filter_epoch(speed, direction, t, start_mjd, end_mjd)
  end

  defnp abs_and_direction_tensors_n(u, v) do
    # We want to represent the direction as the angle where 0º is
    # "up" and 90º is "right". This is not the conventional "math"
    # angle, but its complement instead.

    # We can achieve these results by loading (u, v) as imaginary and
    # real parts of a complex number. This provides a way to easily calculate
    # the angles in the way we desire, because we can think of the resulting
    # numbers as vectors in a space where the x coordinate is the vertical axis
    # and the y coordinate is the horizontal axis, lining up with the definition
    # above.

    # This also avoids the issue where `Nx.atan2/2` wraps angles around due to domain
    # restrictions.

    complex_velocity = Nx.complex(v, u)

    speed = Nx.abs(complex_velocity)
    # convert m/s to knots
    speed_kt = speed * 1.94384

    direction_rad = Nx.phase(complex_velocity)

    direction_deg = direction_rad * 180 / @pi
    # Wrap the values so that they're constrained between 0º and 360º

    direction_deg = Nx.select(direction_deg < 0, direction_deg + 360, direction_deg)

    {speed_kt, direction_deg}
  end

  deftransformp filter_epoch(speed, direction, t, start_mjd, end_mjd) do
    idx = Nx.greater_equal(t, start_mjd)
    idx = Nx.logical_and(idx, Nx.less_equal(t, end_mjd))

    take_idx = Nx.argsort(idx, direction: :desc)

    # count is returned as a number which can be used for slicing
    count = Nx.to_number(Nx.sum(idx))
    filter_epoch_n(speed, direction, t, take_idx, count: count)
  end

  defnp filter_epoch_n(speed, direction, t, take_idx, opts \\ []) do
    count = opts[:count]
    speed = speed |> Nx.take(take_idx) |> Nx.slice_along_axis(0, count, axis: 0)
    direction = direction |> Nx.take(take_idx) |> Nx.slice_along_axis(0, count, axis: 0)
    t = t |> Nx.take(take_idx) |> Nx.slice_along_axis(0, count, axis: 0)

    {t, speed, direction}
  end

  defp interpolate_time(%{shape: {n}} = time) do
    t1 = time[0..-2//1]
    t2 = time[1..-1//1]
    idx = Nx.iota({n - 1})

    dt_days = Nx.subtract(t2, t1)

    num_minutes = Nx.ceil(Nx.divide(dt_days, @one_second_in_mjd)) |> Nx.as_type(Nx.type(idx))

    {idx, p_values} = p_values(Nx.stack([idx, num_minutes], axis: 1))

    {interpolate(time, idx, p_values), idx, p_values}
  end

  defp p_values(time) do
    # returns the p_values for interpolation and the
    # corresponding original indices relating to the
    # input time tensor
    {idx, p} =
      time
      |> Nx.to_batched(1)
      |> Enum.map(fn d ->
        idx = d[[0, 0]]
        num_minutes = Nx.to_number(d[[0, 1]])
        {Nx.broadcast(idx, {num_minutes}), Nx.iota({num_minutes}) |> Nx.divide(num_minutes)}
      end)
      |> Enum.unzip()

    {Nx.concatenate(idx), Nx.concatenate(p)}
  end

  defn interpolate(tensor, indices, p) do
    x0 = Nx.take(tensor, indices)
    x1 = Nx.take(tensor, indices + 1)

    x0 * (1 - p) + x1 * p
  end

  defn interpolate_direction(tensor, indices, p) do
    x0 = Nx.take(tensor, indices)
    x1 = Nx.take(tensor, indices + 1)
    Nx.select(p <= 0.5, x0, x1)
  end

  defp render_data(speed, direction, lat, lon, min_lat, min_lon, max_lat, max_lon, zoom_level) do
    step =
      cond do
        zoom_level >= 13.5 -> 1
        zoom_level >= 13 -> 2
        zoom_level >= 12 -> 4
        zoom_level >= 11 -> 8
        true -> 10
      end

    speed
    |> filter_bounding_box(direction, lat, lon, min_lat, min_lon, max_lat, max_lon)
    |> Nx.to_flat_list()
    |> Enum.chunk_every(4)
    |> Enum.reject(fn [_, _, _, s] -> s == 0 end)
    |> Enum.take_every(step)
    |> Enum.map(fn [lon, lat, direction, speed] ->
      %Geodata.Current{lon: lon, lat: lat, direction: direction, speed: speed}
    end)
  end

  deftransformp filter_bounding_box(
                  speed,
                  direction,
                  lat,
                  lon,
                  min_lat,
                  min_lon,
                  max_lat,
                  max_lon
                ) do
    idx =
      Nx.greater_equal(lat, min_lat)
      |> Nx.logical_and(Nx.less_equal(lat, max_lat))
      |> Nx.logical_and(Nx.greater_equal(lon, min_lon))
      |> Nx.logical_and(Nx.less_equal(lon, max_lon))

    take_idx = Nx.argsort(idx, direction: :desc)

    # count is returned as a number which can be used for slicing
    count = Nx.to_number(Nx.sum(idx))

    filter_bounding_box_n(speed, direction, lat, lon, take_idx, count: count)
  end

  defnp filter_bounding_box_n(speed, direction, lat, lon, take_idx, opts \\ []) do
    count = opts[:count]

    speed = speed |> Nx.take(take_idx) |> Nx.slice_along_axis(0, count)
    direction = direction |> Nx.take(take_idx) |> Nx.slice_along_axis(0, count)
    lat = lat |> Nx.take(take_idx) |> Nx.slice_along_axis(0, count)
    lon = lon |> Nx.take(take_idx) |> Nx.slice_along_axis(0, count)

    Nx.stack([lon, lat, direction, speed], axis: 1)
  end
end
