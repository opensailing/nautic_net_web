defmodule Geodata.Current do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.11.0", syntax: :proto3

  field :lat, 1, type: :float
  field :lon, 2, type: :float
  field :speed, 3, type: :float
  field :direction, 4, type: :float
end

defmodule Geodata.GeoData do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.11.0", syntax: :proto3

  field :currents, 1, repeated: true, type: Geodata.Current
end