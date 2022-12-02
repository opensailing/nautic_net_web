defmodule NauticNet.Racing.Boat do
  use NauticNet.Schema

  alias NauticNet.Data.Sensor

  schema "boats" do
    has_many :sensors, Sensor

    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(boat, attrs) do
    boat
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
