defmodule NauticNet.Repo.Migrations.CreateDataPoints do
  use Ecto.Migration

  def change do
    create table(:samples, primary_key: false) do
      add :time, :timestamptz, null: false
      add :type, :text, null: false
      add :boat_id, references(:boats, on_delete: :delete_all, type: :binary_id), null: false
      add :sensor_id, references(:sensors, on_delete: :delete_all, type: :binary_id), null: false

      add :magnitude, :float
      add :angle, :float
      add :position, :geometry
    end

    create index(:samples, [:boat_id])
    create index(:samples, [:sensor_id])
    create index(:samples, [:time])
    create index(:samples, [:type])

    execute(
      "SELECT create_hypertable('samples', 'time', chunk_time_interval => INTERVAL '1 day')",
      "-- do nothing during down()"
    )
  end
end
