defmodule NauticNet.Racing.Race do
  @moduledoc "Schema module for races"
  use NauticNet.Schema

  schema "races" do
    field :ends_at, :utc_datetime
    field :name, :string
    field :starts_at, :utc_datetime
    field :center, Geo.PostGIS.Geometry

    timestamps()
  end

  @doc false
  def changeset(race, attrs) do
    race
    |> cast(attrs, [:name, :starts_at, :ends_at, :center])
    |> validate_required([:name, :starts_at, :ends_at, :center])
  end
end
