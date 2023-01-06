defmodule NauticNet.Repo.Migrations.CreateWindVelocitySamples do
  use Ecto.Migration

  def change do
    create table(:wind_velocity_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reference, :string, null: false
      add :speed_kt, :float, null: false
      add :angle_deg, :float, null: false

      add :data_point_id, references(:data_points, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:wind_velocity_samples, [:data_point_id])
    create index(:wind_velocity_samples, [:reference])
  end
end
