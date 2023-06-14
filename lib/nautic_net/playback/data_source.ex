defmodule NauticNet.Playback.DataSource do
  @moduledoc """
  Represents a measurement that can be displayed directly from the sample data.
  """
  defstruct [:id, :name, :type, :selected_sensor, sensors: []]
end
