defmodule NauticNet.Data.Sensor do
  @moduledoc "Schema module for sensors"
  use NauticNet.Schema

  alias NauticNet.Data.Sample
  alias NauticNet.Racing.Boat

  schema "sensors" do
    belongs_to :boat, Boat
    has_many :samples, Sample

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
