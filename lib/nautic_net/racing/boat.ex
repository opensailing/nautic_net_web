defmodule NauticNet.Racing.Boat do
  use NauticNet.Schema

  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor

  schema "boats" do
    has_many :sensors, Sensor
    has_many :samples, Sample

    field :name, :string
    field :identifier, :string

    timestamps()
  end

  @doc false
  def changeset(boat, attrs) do
    boat
    |> cast(attrs, [:name, :identifier])
    |> validate_required([:name, :identifier])
    |> unique_constraint(:identifier)
  end
end
