defmodule Runestone.Telemetry do
  @moduledoc """
  Telemetry helper module for emitting events.
  """

  def emit(event_name, measurements, metadata \\ %{}) do
    :telemetry.execute(
      [:runestone | List.wrap(event_name)],
      measurements,
      metadata
    )
  end
end