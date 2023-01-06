defmodule NauticNet.Data.VelocitySample do
  use NauticNet.Schema

  alias NauticNet.Data.DataPoint

  @references [
    :none,
    true,
    :magnetic
  ]

  schema "velocity_samples" do
    belongs_to :data_point, DataPoint

    field :speed_kt, :float
    field :angle_deg, :float
    field :reference, Ecto.Enum, values: @references
  end
end
