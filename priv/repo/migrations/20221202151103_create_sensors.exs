defmodule NauticNet.Repo.Migrations.CreateSensors do
  use Ecto.Migration

  def change do
    create table(:sensors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :hardware_identifier, :string
      add :boat_id, references(:boats, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:sensors, [:boat_id])
    create index(:sensors, [:hardware_identifier])
  end
end
