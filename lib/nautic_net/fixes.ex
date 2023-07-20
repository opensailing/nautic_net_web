defmodule NauticNet.Fixes do
  @moduledoc """
  Backend functions for fixing bad data.
  """

  import Ecto.Query

  alias NauticNet.Data.Sample
  alias NauticNet.Repo

  @doc """
  Deletes all :position samples with coordinates that are out-of-bounds.
  """
  def delete_invalid_position_samples do
    Sample
    |> where(
      [s],
      s.type == :position and
        fragment(
          "st_x(?) < -180 or st_x(?) > 180 or st_y(?) < -90 or st_y(?) > 90",
          s.position,
          s.position,
          s.position,
          s.position
        )
    )
    |> Repo.delete_all()
  end
end
