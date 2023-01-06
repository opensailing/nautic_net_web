defmodule NauticNet.Data.HeadingSample do
  use NauticNet.Schema

  alias NauticNet.Data.DataPoint

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
end
