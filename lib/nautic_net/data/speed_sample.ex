defmodule NauticNet.Data.SpeedSample do
  use NauticNet.Schema
  @behaviour NauticNet.Data.SampleSchema

  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.SampleSchema
  alias NauticNet.Protobuf

  schema "speed_samples" do
    belongs_to :data_point, DataPoint

    field :speed_kt, :float
  end

  @impl SampleSchema
  def sample_type, do: :speed

  @impl SampleSchema
  def sample_assoc, do: :speed_sample

  @impl SampleSchema
  def sample_measurements, do: [:speed_water_referenced]

  @impl SampleSchema
  def attrs_from_protobuf_sample(%Protobuf.SpeedSample{} = sample) do
    {:ok, %{speed_kt: sample.speed_kt}}
  end

  def attrs_from_protobuf_sample(_), do: :error
end
