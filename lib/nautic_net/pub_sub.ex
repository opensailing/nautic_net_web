defmodule NauticNet.PubSub do
  @moduledoc """
  Convenience functions for PubSub.
  """
  def subscribe_to_boat(boat) do
    Phoenix.PubSub.subscribe(NauticNet.PubSub, "boat:#{boat.id}")
  end

  def unsubscribe_from_boat(boat) do
    Phoenix.PubSub.unsubscribe(NauticNet.PubSub, "boat:#{boat.id}")
  end
end
