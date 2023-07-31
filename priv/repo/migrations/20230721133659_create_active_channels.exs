defmodule NauticNet.Repo.Migrations.CreateActiveChannels do
  use Ecto.Migration

  def change do
    up = """
    CREATE MATERIALIZED VIEW active_channels AS
      SELECT DISTINCT DATE(time) as utc_date, boat_id, sensor_id, type FROM samples
    """

    down = """
    DROP MATERIALIZED VIEW active_channels
    """

    execute(up, down)
  end
end
