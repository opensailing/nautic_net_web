defmodule NauticNet.Repo.Migrations.CreateSpeedSamples do
  use Ecto.Migration

  def change do
    create table(:speed_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :speed_kt, :float, null: false

      add :data_point_id, references(:data_points, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:speed_samples, [:data_point_id])
  end
end
