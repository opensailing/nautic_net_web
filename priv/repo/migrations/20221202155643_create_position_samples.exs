defmodule NauticNet.Repo.Migrations.CreatePositionSamples do
  use Ecto.Migration

  def change do
    create table(:position_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :point, :geometry
      add :data_point_id, references(:data_points, on_delete: :delete_all, type: :binary_id)
    end

    create index(:position_samples, [:data_point_id])
    create index(:position_samples, [:point], using: :gist)
  end
end
