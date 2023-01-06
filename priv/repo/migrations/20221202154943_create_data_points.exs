defmodule NauticNet.Repo.Migrations.CreateDataPoints do
  use Ecto.Migration

  def change do
    create table(:data_points, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :timestamp, :utc_datetime_usec, null: false
      add :type, :string, null: false
      add :field, :string, null: false
      add :boat_id, references(:boats, on_delete: :delete_all, type: :binary_id), null: false
      add :sensor_id, references(:sensors, on_delete: :delete_all, type: :binary_id), null: false
    end

    create index(:data_points, [:boat_id])
    create index(:data_points, [:sensor_id])
    create index(:data_points, [:timestamp])
    create index(:data_points, [:type])
    create index(:data_points, [:field])
    create index(:data_points, [:type, :field])
  end
end
