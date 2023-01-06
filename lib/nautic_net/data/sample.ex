defmodule NauticNet.Data.Sample do
  use NauticNet.Schema

  alias NauticNet.Data.Sensor
  alias NauticNet.Protobuf
  alias NauticNet.Racing.Boat

  @type_values [
    :heading,
    :position,
    :speed,
    :velocity,
    :water_depth,
    :wind_velocity
  ]

  @measurement_values [
    :heading,
    :position,
    :speed,
    :velocity,
    :water_depth,
    :wind_velocity
  ]

  @reference_values [
    # Any:
    :none,
    # Heading and wind:
    :true_north,
    :magnetic_north,
    # Wind:
    :apparent,
    :true_north_boat,
    :true_north_water,
    # Speed and velocity:
    :water,
    :ground
  ]

  @primary_key false
  schema "samples" do
    belongs_to :boat, Boat
    belongs_to :sensor, Sensor

    # The name of the specific measurement
    field :measurement, Ecto.Enum, values: @measurement_values

    # The moment the sample was taken
    field :time, :utc_datetime_usec

    # The data type of this sample
    field :type, Ecto.Enum, values: @type_values

    # The point of reference for this measurement (speed, velocity, wind_velocity, heading)
    field :reference, Ecto.Enum, values: @reference_values

    ### Sample fields, set sparsely depending on :type

    # velocity, wind_velocity
    field :angle_deg, :float

    # water_depth
    field :depth_m, :float

    # heading
    field :heading_deg, :float

    # position
    field :position, Geo.PostGIS.Geometry

    # speed, velocity, wind_velocity
    field :speed_kt, :float
  end

  def attrs_from_protobuf_sample(%Protobuf.HeadingSample{} = sample) do
    {:ok,
     %{
       type: :heading,
       heading_deg: sample.heading_deg,
       reference: decode_protobuf_enum(sample.reference)
     }}
  end

  def attrs_from_protobuf_sample(%Protobuf.PositionSample{} = sample) do
    {:ok,
     %{type: :position, position: %Geo.Point{coordinates: {sample.latitude, sample.longitude}}}}
  end

  def attrs_from_protobuf_sample(%Protobuf.SpeedSample{} = sample) do
    {:ok, %{type: :speed, speed_kt: sample.speed_kt}}
  end

  def attrs_from_protobuf_sample(%Protobuf.VelocitySample{} = sample) do
    {:ok,
     %{
       type: :velocity,
       speed_kt: sample.speed_kt,
       angle_deg: sample.angle_deg,
       reference: decode_protobuf_enum(sample.reference)
     }}
  end

  def attrs_from_protobuf_sample(%Protobuf.WaterDepthSample{} = sample) do
    {:ok, %{type: :water_depth, depth_m: sample.depth}}
  end

  def attrs_from_protobuf_sample(%Protobuf.WindVelocitySample{} = sample) do
    {:ok,
     %{
       type: :wind_velocity,
       speed_kt: sample.speed_kt,
       angle_deg: sample.angle_deg,
       reference: decode_protobuf_enum(sample.reference)
     }}
  end

  def attrs_from_protobuf_sample(_), do: :error

  defp decode_protobuf_enum(:WIND_REFERENCE_NONE), do: :none
  defp decode_protobuf_enum(:WIND_REFERENCE_TRUE), do: :true_north
  defp decode_protobuf_enum(:WIND_REFERENCE_MAGNETIC), do: :magnetic_north
  defp decode_protobuf_enum(:WIND_REFERENCE_APPARENT), do: :apparent
  defp decode_protobuf_enum(:WIND_REFERENCE_TRUE_BOAT), do: :true_north_boat
  defp decode_protobuf_enum(:WIND_REFERENCE_TRUE_WATER), do: :true_north_water

  defp decode_protobuf_enum(:DIRECTION_REFERENCE_NONE), do: :none
  defp decode_protobuf_enum(:DIRECTION_REFERENCE_TRUE), do: :true_north
  defp decode_protobuf_enum(:DIRECTION_REFERENCE_MAGNETIC), do: :magnetic_north

  defp decode_protobuf_enum(unknown),
    do: raise(ArgumentError, "Unexpected protobuf enum value #{inspect(unknown)}")
end
