defmodule NauticNet.Playback.Signal do
  @moduledoc """
  Data samples and presentation concerns for displaying a particular Channel.
  """
  defstruct [
    # %Channel{}
    channel: nil,

    # The current sample being inspected
    latest_sample: nil,

    # If the signal is shown at all
    visible?: false,

    # Hex foreground color
    color: "#000000"
  ]
end
