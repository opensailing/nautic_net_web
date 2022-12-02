defmodule NauticNet.Util do
  @moduledoc """
  The junk drawer.
  """
  def datetime_to_protobuf_timestamp(%DateTime{} = datetime) do
    nanos = elem(datetime.microsecond, 0) * 1000

    Google.Protobuf.Timestamp.new!(
      seconds: DateTime.to_unix(datetime, :second),
      nanos: nanos
    )
  end

  def protobuf_timestamp_to_datetime(%Google.Protobuf.Timestamp{} = timestamp) do
    timestamp.seconds
    |> DateTime.from_unix!()
    |> DateTime.add(timestamp.nanos, :nanosecond)
  end
end
