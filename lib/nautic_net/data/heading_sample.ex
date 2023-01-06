defmodule NauticNet.Data.HeadingSample do
  use NauticNet.Schema
  @behaviour NauticNet.Data.SampleSchema

  alias NauticNet.Protobuf
  alias NauticNet.Data.DataPoint
  alias NauticNet.Data.SampleSchema

  @references [
    :none,
    true,
    :magnetic
  ]

  schema "heading_samples" do
    belongs_to :data_point, DataPoint

    field :heading_deg, :float
    field :reference, Ecto.Enum, values: @references
  end

  @impl SampleSchema
  def sample_type, do: :heading

  @impl SampleSchema
  def sample_assoc, do: :heading_sample

  @impl SampleSchema
  def sample_measurements, do: [:heading]

  @impl SampleSchema
  def attrs_from_protobuf_sample(%Protobuf.HeadingSample{} = sample) do
    {:ok,
     %{
       heading_deg: sample.heading_deg,
       reference: NauticNet.Data.SampleSchema.decode_protobuf_enum(sample.reference)
     }}
  end

  def attrs_from_protobuf_sample(_), do: :error
end
