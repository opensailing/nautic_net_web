defmodule NauticNet.Racing.Boat do
  use NauticNet.Schema

  schema "boats" do
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
