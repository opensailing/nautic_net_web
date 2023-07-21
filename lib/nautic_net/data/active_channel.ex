defmodule NauticNet.Data.ActiveChannel do
  @moduledoc """
  Materialized view to determine which signal channels were active on any UTC date.

  It must be manually refreshed. See `NauticNet.MaterializedViewRefresher`.
  """
  use NauticNet.Schema

  schema "active_channels" do
    belongs_to :boat, NauticNet.Racing.Boat
    belongs_to :sensor, NauticNet.Data.Sensor

    field :utc_date, :date
    field :type, Ecto.Enum, values: Enum.map(NauticNet.Data.Sample.types(), & &1.type)
  end
end
