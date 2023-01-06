defmodule NauticNet.Data.DataPoint do
  use NauticNet.Schema

  alias NauticNet.Racing.Boat
  alias NauticNet.Data.SampleSchema
  alias NauticNet.Data.Sensor

  @sample_schemas SampleSchema.sample_schemas()
  @valid_sample_types Enum.map(@sample_schemas, & &1.sample_type())
  @valid_measurements Enum.flat_map(@sample_schemas, & &1.sample_measurements())

  schema "data_points" do
    belongs_to :boat, Boat
    belongs_to :sensor, Sensor

    for schema <- @sample_schemas do
      has_one schema.sample_assoc(), schema
    end

    field :timestamp, :utc_datetime_usec
    field :measurement, Ecto.Enum, values: @valid_measurements
    field :type, Ecto.Enum, values: @valid_sample_types
  end

  def sample_type(schema) when is_atom(schema) do
    schema.sample_type()
  end
end
