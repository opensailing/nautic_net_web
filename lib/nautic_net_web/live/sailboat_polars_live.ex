defmodule NauticNetWeb.SailboatPolarsLive do
  use NauticNetWeb, :live_view

  alias Explorer.DataFrame, as: DF

  alias NauticNet.SailboatPolars

  defmodule Polars do
    defstruct [
      :id,
      :twa,
      :boat_speed_4,
      :awa_4,
      :boat_speed_6,
      :awa_6,
      :boat_speed_8,
      :awa_8,
      :boat_speed_10,
      :awa_10,
      :boat_speed_12,
      :awa_12,
      :boat_speed_16,
      :awa_16,
      :boat_speed_20,
      :awa_20,
      :boat_speed_24,
      :awa_24
    ]
  end

  defmodule RunBeatPolars do
    defstruct [
      :id,
      :tws,
      :beat_awa,
      :beat_aws,
      :beat_boat_speed,
      :run_awa,
      :run_aws,
      :run_boat_speed
    ]
  end

  def mount(_, _, socket) do
    socket = load(socket, :sailboat_polars)
    Process.send_after(self(), :refresh, :timer.seconds(10))

    {:ok, socket}
  end

  defp load(socket, :sailboat_polars) do
    {polars_df, run_beat_df} =
      SailboatPolars.load(Path.join(:code.priv_dir(:nautic_net), "sample_sailboat_csv.csv"))

    assign(socket,
      sailboat_polars: polars_df_to_params(polars_df),
      run_beat_polars: run_beat_polars_df_to_params(run_beat_df)
    )
  end

  defp polars_df_to_params(df) do
    df
    |> DF.to_rows()
    |> Enum.with_index(fn row, idx ->
      row
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> then(&struct!(Polars, [{:id, idx} | &1]))
    end)
  end

  defp run_beat_polars_df_to_params(df) do
    df
    |> DF.to_rows()
    |> Enum.with_index(fn row, idx ->
      row
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> then(&struct!(RunBeatPolars, [{:id, idx} | &1]))
    end)
  end

  attr(:speed, :any, default: nil)
  attr(:angle, :any, default: nil)
  slot(:inner_block, required: false)

  defp render_speed_awa(assigns) do
    ~H"""
    <p><.float2 value={@speed} /> kts</p>
    <p><.float2 value={@angle} />°</p>
    """
  end

  attr(:value, :any, default: nil)
  slot(:inner_block, required: false)

  defp float2(assigns) do
    ~H"""
    <span><%= :erlang.float_to_binary(@value, decimals: 2) %></span>
    """
  end
end
