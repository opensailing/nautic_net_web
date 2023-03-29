defmodule NauticNet.Playback.DataSource do
  @moduledoc """
  Represents a measurement that can be displayed directly from the sample data.
  """
  defstruct [:id, :name, :measurement, :reference, :selected_sensor, :latest_sample, sensors: []]
end
