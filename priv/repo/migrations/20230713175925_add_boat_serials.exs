defmodule NauticNet.Repo.Migrations.AddBoatSerials do
  use Ecto.Migration

  def change do
    alter table(:boats) do
      add :serial, :string
    end
  end
end
