defmodule App.Worker.ErrorReporter do
  @moduledoc """
  Sends failed Oban jobs to Honeybadger. Oban rescues job errors, so they never reach
  the logger that reports crashes.
  """

  def attach do
    :telemetry.attach(
      "honeybadger-oban-errors",
      [:oban, :job, :exception],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:oban, :job, :exception], _measurements, meta, _config) do
    context = Map.take(meta.job, [:id, :args, :queue, :worker, :attempt])
    Honeybadger.notify(meta.reason, metadata: context, stacktrace: meta.stacktrace)
  end
end
