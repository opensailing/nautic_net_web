defmodule NauticNet.Data.WaterDepthSample do
  use NauticNet.Schema
  @behaviour NauticNet.Data.SampleSchema

  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.SampleSchema
  alias NauticNet.Protobuf

  schema "water_depth_samples" do
    belongs_to :data_point, DataPoint

    field :depth_m, :float
  end

  @impl SampleSchema
  def sample_type, do: :water_depth

  @impl SampleSchema
  def sample_assoc, do: :water_depth_sample

  @impl SampleSchema
  def sample_measurements, do: [:water_depth]

  @impl SampleSchema
  def attrs_from_protobuf_sample(%Protobuf.WaterDepthSample{} = sample) do
    {:ok, %{depth_m: sample.depth}}
  end

  def attrs_from_protobuf_sample(_), do: :error
end
