defmodule NauticNet.Playback.Signal do
  @moduledoc """
  Data samples and presentation concerns for displaying a particular Channel.
  """
  defstruct [
    # %Channel{}
    channel: nil,

    # List of %Sample{} (only preload if necessary)
    samples: [],

    # List of coordinate maps (for :position channels only)
    coordinates: [],

    # The current sample being inspected
    latest_sample: nil,

    # If the signal is shown at all
    visible?: true,

    # Hex foreground color
    color: "#000000"
  ]
end
