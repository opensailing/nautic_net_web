defmodule NauticNet.Repo.Migrations.AddBoatsPrimaryLocationSensorId do
  use Ecto.Migration

  def change do
    alter table(:boats) do
      add :primary_position_sensor_id,
          references(:sensors, on_delete: :nilify_all, type: :binary_id)
    end
  end
end
