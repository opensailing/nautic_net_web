defmodule NauticNet.Data.Sensor do
  use NauticNet.Schema

  alias NauticNet.Racing.Boat

  schema "sensors" do
    belongs_to :boat, Boat

    field :hardware_identifier, :string
    field :name, :string

    timestamps()
  end

  @doc false
  def insert_changeset(sensor, attrs) do
    sensor
    |> cast(attrs, [:boat_id, :name, :hardware_identifier])
    |> validate_required([:boat_id, :name, :hardware_identifier])
  end

  @doc false
  def update_changeset(sensor, attrs) do
    sensor
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
