defmodule NauticNet.Playback.Channel do
  @moduledoc """
  An identifier representing a set of samples that can be selected from a particular
  combination of boat, sensor, and measurement type.
  """

  defstruct [
    # A unique string for this boat-sensor-type
    :id,

    # %Boat{}
    :boat,

    # %Sensor{}
    :sensor,

    # an atom corresponding to a Sample type
    :type,

    # A friendly human name (see Sample.types/0)
    :name,

    # The magnitude unit stored in the DB (see Sample.types/0)
    :unit
  ]

  alias NauticNet.Data.Sample
  alias NauticNet.Data.Sensor
  alias NauticNet.Racing.Boat

  def new(%Boat{} = boat, %Sensor{} = sensor, type) when is_atom(type) do
    type_info = Sample.get_type_info(type)

    %__MODULE__{
      id: "#{boat.id}-#{sensor.id}-#{type}",
      boat: boat,
      sensor: sensor,
      type: type,
      unit: if(type_info, do: type_info.unit, else: :none),
      name: if(type_info, do: type_info.name, else: "Unnamed Channel")
    }
  end
end
