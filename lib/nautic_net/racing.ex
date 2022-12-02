defmodule NauticNet.Racing do
  @moduledoc """
  Core model CRUD.
  """
  alias NauticNet.Racing.Boat
  alias NauticNet.Racing.Race
  alias NauticNet.Repo

  ### Races

  def create_race(params) do
    %Race{}
    |> Race.changeset(params)
    |> Repo.insert()
  end

  ### Boats

  def get_or_create_boat_by_identifier(identifier, preloads \\ []) do
    case Repo.get_by(Boat, identifier: identifier) do
      nil ->
        {:ok, boat} = create_boat(%{name: identifier, identifier: identifier})
        boat

      %Boat{} = boat ->
        boat
    end
    |> Repo.preload(preloads)
  end

  def create_boat(params) do
    %Boat{}
    |> Boat.changeset(params)
    |> Repo.insert()
  end
end
