defmodule NauticNet.Repo.Migrations.CreateDataPoints do
  use Ecto.Migration

  defp create_enum_type(name, values) do
    values_list = values |> Enum.map(&"'#{&1}'") |> Enum.join(", ")

    create_query = "CREATE TYPE #{name} AS ENUM (#{values_list})"
    drop_query = "DROP TYPE #{name}"

    execute(create_query, drop_query)
  end

  def change do
    create_enum_type(:sample_type, [
      :heading,
      :position,
      :speed,
      :velocity,
      :water_depth,
      :wind_velocity
    ])

    create_enum_type(:measurement_type, [
      :heading,
      :position,
      :speed,
      :velocity,
      :water_depth,
      :wind_velocity
    ])

    create_enum_type(:reference, [
      :none,
      :true_north,
      :magnetic_north,
      :apparent,
      :true_north_boat,
      :true_north_water,
      :water,
      :ground
    ])

    create table(:data_points, primary_key: false) do
      add :time, :timestamptz, null: false
      add :type, :sample_type, null: false
      add :measurement, :measurement_type, null: false
      add :boat_id, references(:boats, on_delete: :delete_all, type: :binary_id), null: false
      add :sensor_id, references(:sensors, on_delete: :delete_all, type: :binary_id), null: false

      ### Sample fields

      # velocity, wind velocity
      add :angle_deg, :float

      # water depth
      add :depth_m, :float

      # heading
      add :heading_deg, :float

      # position
      add :position, :geometry

      # velocity, wind velocity, heading
      add :reference, :reference

      # speed, velocity, wind velocity
      add :speed_kt, :float
    end

    create index(:data_points, [:boat_id])
    create index(:data_points, [:sensor_id])
    create index(:data_points, [:time])
    create index(:data_points, [:type])
    create index(:data_points, [:measurement])
    create index(:data_points, [:type, :measurement])
    create index(:data_points, [:position], using: :gist)

    execute(
      "SELECT create_hypertable('data_points', 'time', chunk_time_interval => INTERVAL '1 day')",
      "-- do nothing during down()"
    )
  end
end
