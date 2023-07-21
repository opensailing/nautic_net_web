defmodule NauticNet.LocalDate do
  @moduledoc """
  Represents a Date in a specific timezone.
  """
  @enforce_keys [:date, :timezone]
  defstruct [:date, :timezone]

  @doc """
  Returns a list of UTC Dates that overlap with the local date.
  """
  def utc_dates(%__MODULE__{} = local_date) do
    {utc_start, utc_end} = utc_interval(local_date)

    Enum.uniq([Timex.to_date(utc_start), Timex.to_date(utc_end)])
  end

  @doc """
  Return a tuple of UTC DateTimes at the beginning and end of the local date.
  """
  def utc_interval(%__MODULE__{} = local_date) do
    {local_start, local_end} = local_interval(local_date)

    {Timex.to_datetime(local_start, "Etc/UTC"), Timex.to_datetime(local_end, "Etc/UTC")}
  end

  @doc """
  Returns a tuple of local DateTimes at the beginning and end of the date.
  """
  def local_interval(%__MODULE__{} = local_date) do
    {
      local_date.date |> Timex.to_datetime(local_date.timezone) |> Timex.beginning_of_day(),
      local_date.date |> Timex.to_datetime(local_date.timezone) |> Timex.end_of_day()
    }
  end
end
