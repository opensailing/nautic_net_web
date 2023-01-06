defmodule NauticNet.Data.DataPoint do
  use NauticNet.Schema

  alias NauticNet.Racing.Boat
  alias NauticNet.Data.HeadingSample
  alias NauticNet.Data.PositionSample
  alias NauticNet.Data.WindVelocitySample
  alias NauticNet.Data.Sensor

  @sample_types %{
    heading: {:heading_sample, HeadingSample},
    position: {:position_sample, PositionSample},
    wind_velocity: {:wind_velocity_sample, WindVelocitySample}
  }

  schema "data_points" do
    belongs_to :boat, Boat
    belongs_to :sensor, Sensor

    has_one :heading_sample, HeadingSample
    has_one :position_sample, PositionSample
    has_one :wind_velocity_sample, WindVelocitySample

    field :timestamp, :utc_datetime_usec
    field :type, Ecto.Enum, values: Map.keys(@sample_types)
  end

  def insert_changeset(data_point, sample, params) do
    data_point
    |> cast(params, [:boat_id, :sensor_id, :timestamp])
    |> validate_required([:boat_id, :sensor_id, :timestamp])
    |> put_sample_assoc(sample)
  end

  defp put_sample_assoc(%Ecto.Changeset{} = changeset, %schema{} = sample) do
    {type, {assoc, _schema}} =
      Enum.find(@sample_types, fn {_type, {_assoc, s}} -> s == schema end)

    changeset
    |> put_change(:type, type)
    |> put_assoc(assoc, sample)
  end

  def sample_type(schema) when is_atom(schema) do
    {type, {_assoc, _schema}} =
      Enum.find(@sample_types, fn {_type, {_assoc, s}} -> s == schema end)

    type
  end
end
