defmodule NauticNet.Repo.Migrations.CreateHeadingSamples do
  use Ecto.Migration

  def change do
    create table(:heading_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reference, :string, null: false
      add :heading_deg, :float, null: false

      add :data_point_id, references(:data_points, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:heading_samples, [:data_point_id])
    create index(:heading_samples, [:reference])
  end
end
