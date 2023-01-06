defmodule NauticNet.DataIngest.ProtobufDecode do
  alias NauticNet.Data
  alias NauticNet.Protobuf

  ### Data Mapping

  # Converts a protobuf sample a DB sample that is ready for insertion. Returns a tuple like {:ok, MySchema, attrs_map}
  def to_sample_attrs({:position, %Protobuf.PositionSample{} = sample}) do
    {:ok, Data.PositionSample,
     %{
       point: %Geo.Point{coordinates: {sample.latitude, sample.longitude}}
     }}
  end

  def to_sample_attrs({:wind_velocity, %Protobuf.WindVelocitySample{} = sample}) do
    {:ok, Data.WindVelocitySample,
     %{
       speed_kt: sample.speed_kt,
       angle_deg: sample.angle_deg,
       reference: decode_protobuf_enum(sample.reference)
     }}
  end

  def to_sample_attrs({:heading, %Protobuf.HeadingSample{} = sample}) do
    {:ok, Data.HeadingSample,
     %{
       heading_deg: sample.heading_deg,
       reference: decode_protobuf_enum(sample.reference)
     }}
  end

  def to_sample_attrs(_unknown), do: :error

  ### Private Conversion Helpers

  # Convert protobuf enum constants into Ecto.Enum values

  # WindVelocitySample
  defp decode_protobuf_enum(:WIND_REFERENCE_NONE), do: :none
  defp decode_protobuf_enum(:WIND_REFERENCE_TRUE), do: true
  defp decode_protobuf_enum(:WIND_REFERENCE_MAGNETIC), do: :magnetic
  defp decode_protobuf_enum(:WIND_REFERENCE_APPARENT), do: :apparent
  defp decode_protobuf_enum(:WIND_REFERENCE_TRUE_BOAT), do: :true_boat
  defp decode_protobuf_enum(:WIND_REFERENCE_TRUE_WATER), do: :true_water

  # HeadingSample
  defp decode_protobuf_enum(:DIRECTION_REFERENCE_NONE), do: :none
  defp decode_protobuf_enum(:DIRECTION_REFERENCE_TRUE), do: true
  defp decode_protobuf_enum(:DIRECTION_REFERENCE_MAGNETIC), do: :magnetic

  defp decode_protobuf_enum(unknown),
    do: raise("Unexpected protobuf enum value #{inspect(unknown)}")
end
