defmodule NauticNet.Data.SampleSchema do
  @moduledoc """
  Behaviour and helper functions for Ecto schemas that map 1-to-1 with Protobuf sample types.
  """

  @sample_schemas [
    NauticNet.Data.HeadingSample,
    NauticNet.Data.PositionSample,
    NauticNet.Data.VelocitySample,
    NauticNet.Data.WindVelocitySample
  ]

  @doc """
  Returns the value for the DataPoint :type field.
  """
  @callback sample_type :: atom

  @doc """
  Returns the name of the DataPoint assoc.
  """
  @callback sample_assoc :: atom

  @doc """
  Returns a list of valid values for DataPoint :measurement field.
  """
  @callback sample_measurements :: [atom]

  @doc """
  Converts a protobuf schema into attrs that can be inserted directly into the database.
  """
  @callback attrs_from_protobuf_sample(struct) :: {:ok, map} | :error

  def sample_schemas, do: @sample_schemas
  def sample_type(schema), do: schema.sample_type()
  def sample_assoc(schema), do: schema.sample_assoc()
  def sample_measurements(schema), do: schema.sample_measurements()

  def attrs_from_protobuf_sample(protobuf_sample) do
    Enum.find_value(@sample_schemas, :error, fn schema ->
      case schema.attrs_from_protobuf_sample(protobuf_sample) do
        {:ok, attrs} -> {:ok, schema, attrs}
        :error -> false
      end
    end)
  end

  @doc """
  Convert protobuf enum constants into Ecto.Enum values.
  """
  # WindVelocitySample
  def decode_protobuf_enum(:WIND_REFERENCE_NONE), do: :none
  def decode_protobuf_enum(:WIND_REFERENCE_TRUE), do: true
  def decode_protobuf_enum(:WIND_REFERENCE_MAGNETIC), do: :magnetic
  def decode_protobuf_enum(:WIND_REFERENCE_APPARENT), do: :apparent
  def decode_protobuf_enum(:WIND_REFERENCE_TRUE_BOAT), do: :true_boat
  def decode_protobuf_enum(:WIND_REFERENCE_TRUE_WATER), do: :true_water

  # HeadingSample
  def decode_protobuf_enum(:DIRECTION_REFERENCE_NONE), do: :none
  def decode_protobuf_enum(:DIRECTION_REFERENCE_TRUE), do: true
  def decode_protobuf_enum(:DIRECTION_REFERENCE_MAGNETIC), do: :magnetic

  def decode_protobuf_enum(unknown),
    do: raise("Unexpected protobuf enum value #{inspect(unknown)}")
end
