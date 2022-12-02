defmodule NauticNet.Repo.Migrations.CreateRaces do
  use Ecto.Migration

  def change do
    create table(:races, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :center, :geography, null: false

      timestamps()
    end

    create index(:races, [:starts_at])
    create index(:races, [:ends_at])
    create index(:races, [:starts_at, :ends_at])
    create index(:races, [:center], using: :gist)
  end
end
