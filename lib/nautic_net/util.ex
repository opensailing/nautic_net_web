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

  # If the timestamp is zero, then the uploading device didn't have a clock, so the best we can do is assign it to "now"
  def protobuf_timestamp_to_datetime(%Google.Protobuf.Timestamp{nanos: 0, seconds: 0}) do
    DateTime.utc_now()
  end

  def protobuf_timestamp_to_datetime(%Google.Protobuf.Timestamp{} = timestamp) do
    (timestamp.seconds * 1_000_000)
    |> DateTime.from_unix!(:microsecond)
    |> DateTime.add(timestamp.nanos, :nanosecond)
  end
end
