defmodule NauticNet.Repo.Migrations.CreateBoats do
  use Ecto.Migration

  def change do
    create table(:boats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :identifier, :string, null: false

      timestamps()
    end

    create index(:boats, [:identifier], unique: true)
  end
end
