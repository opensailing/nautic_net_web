defmodule NauticNet.Repo.Migrations.CreateWaterDepthSamples do
  use Ecto.Migration

  def change do
    create table(:water_depth_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :depth_m, :float, null: false

      add :data_point_id, references(:data_points, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:water_depth_samples, [:data_point_id])
  end
end
