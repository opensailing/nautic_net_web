defmodule NauticNet.Data.Sensor do
  use NauticNet.Schema

  alias NauticNet.Data.DataPoint
  alias NauticNet.Racing.Boat

  schema "sensors" do
    belongs_to :boat, Boat
    has_many :data_points, DataPoint

    field :hardware_identifier, :string
    field :name, :string

    timestamps()
  end

  @doc false
  def insert_changeset(sensor, params) do
    sensor
    |> cast(params, [:name, :hardware_identifier])
    |> validate_required([:name, :hardware_identifier])
  end
end
