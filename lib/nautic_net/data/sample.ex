defmodule NauticNet.Data.Sample do
  use NauticNet.Schema

  alias NauticNet.Data.Sensor
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
         type: :heel,
         angle: Protobuf.Convert.decode_unit(rover_data.heel - 90, :ddeg, :rad)
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
end
