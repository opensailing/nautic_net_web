defmodule NauticNet.Data.PositionSample do
  use NauticNet.Schema
  @behaviour NauticNet.Data.SampleSchema

  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.SampleSchema
  alias NauticNet.Protobuf

  schema "position_samples" do
    belongs_to :data_point, DataPoint

    field :point, Geo.PostGIS.Geometry
  end

  @impl SampleSchema
  def sample_type, do: :position

  @impl SampleSchema
  def sample_assoc, do: :position_sample

  @impl SampleSchema
  def sample_measurements, do: [:position]

  @impl SampleSchema
  def attrs_from_protobuf_sample(%Protobuf.PositionSample{} = sample) do
    {:ok,
     %{
       point: %Geo.Point{coordinates: {sample.latitude, sample.longitude}}
     }}
  end

  def attrs_from_protobuf_sample(_), do: :error
end
