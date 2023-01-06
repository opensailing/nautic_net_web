defmodule NauticNet.Data.VelocitySample do
  use NauticNet.Schema
  @behaviour NauticNet.Data.SampleSchema

  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.SampleSchema
  alias NauticNet.Protobuf

  @direction_references [
    :none,
    true,
    :magnetic
  ]

  schema "velocity_samples" do
    belongs_to :data_point, DataPoint

    field :speed_kt, :float
    field :angle_deg, :float
    field :direction_reference, Ecto.Enum, values: @direction_references
  end

  @impl SampleSchema
  def sample_type, do: :velocity

  @impl SampleSchema
  def sample_assoc, do: :velocity_sample

  @impl SampleSchema
  def sample_measurements, do: [:velocity_over_ground]

  @impl SampleSchema
  def attrs_from_protobuf_sample(%Protobuf.VelocitySample{} = sample) do
    {:ok,
     %{
       speed_kt: sample.speed_kt,
       angle_deg: sample.angle_deg,
       direction_reference: SampleSchema.decode_protobuf_enum(sample.reference)
     }}
  end

  def attrs_from_protobuf_sample(_), do: :error
end
