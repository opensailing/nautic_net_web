defmodule NauticNet.LocalDate do
  @moduledoc """
  Represents a Date in a specific timezone.
  """
  @enforce_keys [:date, :timezone]
  defstruct [:date, :timezone]
end
