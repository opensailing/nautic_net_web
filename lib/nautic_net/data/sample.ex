defmodule NauticNet.Data.Sample do
  @moduledoc "Schema module for taken samples for a given boat and sensor"
  use NauticNet.Schema

  alias NauticNet.Data.Sensor
  alias NauticNet.Playback.Channel
  alias NauticNet.Protobuf
  alias NauticNet.Racing.Boat

  @types [
    %{type: :apparent_wind, name: "Apparent Wind", unit: :m_s},
    %{type: :battery, name: "Battery", unit: :percent},
    %{type: :heel, name: "Heel", unit: :rad},
    %{type: :magnetic_heading, name: "Magnetic Heading", unit: :rad},
    %{type: :position, name: "Position", unit: :position},
    %{type: :rssi, name: "RSSI", unit: :dbm},
    %{type: :speed_through_water, name: "Speed Through Water", unit: :m_s},
    %{type: :true_heading, name: "True Heading", unit: :rad},
    %{type: :true_wind, name: "True Wind", unit: :m_s},
    %{type: :velocity_over_ground, name: "Velocity Over Ground", unit: :m_s},
    %{type: :water_depth, name: "Water Depth", unit: :m}
  ]

  @primary_key false
  schema "samples" do
    belongs_to :boat, Boat
    belongs_to :sensor, Sensor

    # The moment the sample was taken
    field :time, :utc_datetime_usec

    # The data type of this sample
    field :type, Ecto.Enum, values: Enum.map(@types, & &1.type)

    # Unit determined by type
    field :magnitude, :float

    # Radians
    field :angle, :float

    # Lon/lat coordinate (in that order!)
    field :position, Geo.PostGIS.Geometry
  end

  def attrs_from_protobuf_sample({_field, %Protobuf.HeadingSample{} = sample}) do
    type =
      case sample do
        %{angle_reference: :ANGLE_REFERENCE_TRUE_NORTH} -> :true_heading
        _ -> :magnetic_heading
      end

    {:ok,
     [
       %{
         type: type,
         angle: Protobuf.Convert.decode_unit(sample.angle_mrad, :mrad, :rad)
       }
     ]}
  end

  # Throw out obviously-invalid position samples
  def attrs_from_protobuf_sample(
        {_field, %Protobuf.PositionSample{latitude: latitude, longitude: longitude}}
      )
      when latitude < -90 or latitude > 90 or longitude < -180 or longitude > 180 do
    :error
  end

  def attrs_from_protobuf_sample({_field, %Protobuf.PositionSample{} = sample}) do
    {:ok,
     [
       %{
         type: :position,
         # NOTE!!! The ordering of this coordinate tuple in PostGIS is {x, y}, and hence {longitude, latitude}
         position: %Geo.Point{coordinates: {sample.longitude, sample.latitude}}
       }
     ]}
  end

  def attrs_from_protobuf_sample({_field, %Protobuf.SpeedSample{} = sample}) do
    {:ok,
     [
       %{
         type: :speed_through_water,
         magnitude: Protobuf.Convert.decode_unit(sample.speed_cm_s, :cm_s, :m_s)
       }
     ]}
  end

  def attrs_from_protobuf_sample({_field, %Protobuf.VelocitySample{} = sample}) do
    {:ok,
     [
       %{
         type: :velocity_over_ground,
         magnitude: Protobuf.Convert.decode_unit(sample.speed_cm_s, :cm_s, :m_s),
         angle: Protobuf.Convert.decode_unit(sample.angle_mrad, :mrad, :rad)
       }
     ]}
  end

  def attrs_from_protobuf_sample({_field, %Protobuf.WaterDepthSample{} = sample}) do
    {:ok,
     [
       %{
         type: :water_depth,
         magnitude: Protobuf.Convert.decode_unit(sample.depth_cm, :cm, :m)
       }
     ]}
  end

  def attrs_from_protobuf_sample(
        {_field, %Protobuf.WindVelocitySample{wind_reference: :WIND_REFERENCE_APPARENT} = sample}
      ) do
    {:ok,
     [
       %{
         type: :apparent_wind,
         magnitude: Protobuf.Convert.decode_unit(sample.speed_cm_s, :cm_s, :m_s),
         angle: Protobuf.Convert.decode_unit(sample.angle_mrad, :mrad, :rad)
       }
     ]}
  end

  def attrs_from_protobuf_sample(
        {_field,
         %Protobuf.WindVelocitySample{wind_reference: :WIND_REFERENCE_TRUE_NORTH} = sample}
      ) do
    {:ok,
     [
       %{
         type: :true_wind,
         magnitude: Protobuf.Convert.decode_unit(sample.speed_cm_s, :cm_s, :m_s),
         angle: Protobuf.Convert.decode_unit(sample.angle_mrad, :mrad, :rad)
       }
     ]}
  end

  def attrs_from_protobuf_sample(
        {_field, %Protobuf.TrackerSample{rover_data: %Protobuf.RoverData{} = rover_data} = sample}
      ) do
    {:ok,
     [
       %{type: :rssi, magnitude: sample.rssi * 1.0},
       %{
         type: :position,
         # NOTE!!! The ordering of this coordinate tuple in PostGIS is {x, y}, and hence {longitude, latitude}
         position: %Geo.Point{coordinates: {rover_data.longitude, rover_data.latitude}}
       },
       %{
         type: :magnetic_heading,
         angle: Protobuf.Convert.decode_unit(rover_data.heading, :ddeg, :rad)
       },
       %{
         type: :true_heading,
         angle:
           rover_data.heading
           |> Protobuf.Convert.decode_unit(:ddeg, :rad)
           |> magnetic_heading_to_true_heading()
       },
       %{
         type: :heel,
         # Heel is 0 to 1800 (0.0° to 180.0°) so we subtract 900 (90.0°) to normalize it so that
         # 0° is straight-up towards the sky, negative heel is leaning towards port, and positive heel
         # is leaning towards starboard
         angle: Protobuf.Convert.decode_unit(rover_data.heel - 900, :ddeg, :rad)
       },
       %{
         type: :velocity_over_ground,
         magnitude: Protobuf.Convert.decode_unit(rover_data.sog, :dkn, :m_s),
         angle: Protobuf.Convert.decode_unit(rover_data.cog, :ddeg, :rad)
       },

       # Value of 0 implies no data
       if(sample.rover_data.battery != 0,
         do: %{type: :battery, magnitude: sample.rover_data.battery * 1.0}
       )
     ]
     |> Enum.reject(&is_nil/1)}
  end

  def attrs_from_protobuf_sample(_), do: :error

  def types, do: @types

  def get_type_info(type), do: Enum.find(@types, &(&1.type == type))

  defp magnetic_heading_to_true_heading(mag_heading_rad) do
    # TODO: Calculate magnetic declination based on lat/lon... currently hardcoded to Hingham, MA (14.21° W declination)
    declination_deg = -14.21

    # Apply correction, and wrap around
    true_heading_rad = mag_heading_rad - deg2rad(declination_deg)
    :math.fmod(true_heading_rad, :math.pi())
  end

  defp deg2rad(deg), do: deg * :math.pi() / 180

  @doc """
  Returns true if a Sample is aplicable to a Channel.
  """
  def in_channel?(%__MODULE__{} = sample, %Channel{} = channel) do
    sample.boat_id == channel.boat.id and
      sample.sensor_id == channel.sensor.id and
      sample.type == channel.type
  end
end
