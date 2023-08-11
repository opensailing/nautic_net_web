defmodule NauticNet.Racing.Boat do
  @moduledoc "Schema module for boats"
  use NauticNet.Schema

  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor

  schema "boats" do
    has_many :sensors, Sensor
    has_many :samples, Sample

    belongs_to :primary_position_sensor, Sensor

    field :name, :string
    field :identifier, :string
    field :alive_at, :utc_datetime
    field :serial, :string

    timestamps()
  end

  @doc false
  def changeset(boat, attrs) do
    boat
    |> cast(attrs, [:name, :identifier, :serial, :alive_at])
    |> validate_required([:name, :identifier, :serial])
    |> unique_constraint(:identifier)
  end

  @doc """
  Changeset for user updates to boat preferences.
  """
  def user_changeset(boat, attrs) do
    boat
    |> cast(attrs, [:name, :serial, :primary_position_sensor_id])
    |> validate_required([:name, :serial])
  end
end
