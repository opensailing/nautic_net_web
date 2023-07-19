defmodule NauticNet.Repo.Migrations.AddBoatsAliveAt do
  use Ecto.Migration

  def change do
    alter table(:boats) do
      add :alive_at, :utc_datetime
    end
  end
end
