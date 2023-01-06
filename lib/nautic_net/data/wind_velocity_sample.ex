defmodule NauticNet.Data.WindVelocitySample do
  use NauticNet.Schema
  @behaviour NauticNet.Data.SampleSchema

  alias NauticNet.Protobuf
  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.SampleSchema

  @references [
    :none,
    true,
    :magnetic,
    :apparent,
    :true_boat,
    :true_water
  ]

  schema "wind_velocity_samples" do
    belongs_to :data_point, DataPoint

    field :speed_kt, :float
    field :angle_deg, :float
    field :reference, Ecto.Enum, values: @references
  end

  @impl SampleSchema
  def sample_type, do: :wind_velocity

  @impl SampleSchema
  def sample_assoc, do: :wind_velocity_sample

  @impl SampleSchema
  def sample_measurements, do: [:wind_velocity]

  @impl SampleSchema
  def attrs_from_protobuf_sample(%Protobuf.WindVelocitySample{} = sample) do
    {:ok,
     %{
       speed_kt: sample.speed_kt,
       angle_deg: sample.angle_deg,
       reference: SampleSchema.decode_protobuf_enum(sample.reference)
     }}
  end

  def attrs_from_protobuf_sample(_), do: :error
end
