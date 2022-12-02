defmodule NauticNet.Data.PositionSample do
  use NauticNet.Schema

  alias NauticNet.Data.DataPoint

  schema "position_samples" do
    belongs_to :data_point, DataPoint

    field :point, Geo.PostGIS.Geometry
  end
end
