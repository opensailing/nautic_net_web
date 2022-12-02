defmodule NauticNet.Data.PositionSample do
  use NauticNet.Schema

  alias NauticNet.Data.DataPoint

  schema "position_samples" do
    belongs_to :data_point, DataPoint

    field :coordinate, Geo.PostGIS.Geometry

    timestamps()
  end
end
