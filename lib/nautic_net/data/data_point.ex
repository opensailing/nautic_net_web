defmodule NauticNet.Data.DataPoint do
  use NauticNet.Schema

  alias NauticNet.Racing.Boat
  alias NauticNet.Racing.Race
  alias NauticNet.Data.PositionSample
  alias NauticNet.Data.Sensor

  schema "data_points" do
    belongs_to :boat, Boat
    belongs_to :sensor, Sensor
    belongs_to :race, Race

    has_one :position_sample, PositionSample

    field :timestamp, :utc_datetime_usec
    field :type, Ecto.Enum, values: [:position]

    timestamps()
  end
end
