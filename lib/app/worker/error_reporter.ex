defmodule App.Worker.ErrorReporter do
  @moduledoc """
  Sends failed Oban jobs to Honeybadger. Oban rescues job errors, so they never reach
  the logger that reports crashes. A job is reported once it has no attempts left
  (`state: :discard`), not on each attempt that a retry may still fix. An email the mail
  service blocks for good isn't ours to fix: the team sees it in Needs attention.
  """

  def attach do
    :telemetry.attach(
      "honeybadger-oban-errors",
      [:oban, :job, :exception],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event(
        [:oban, :job, :exception],
        _measurements,
        %{reason: %Oban.PerformError{reason: {:error, {:email_problem, _problem}}}},
        _config
      ),
      do: :ok

  def handle_event([:oban, :job, :exception], _measurements, %{state: :discard} = meta, _config) do
    context = Map.take(meta.job, [:id, :args, :queue, :worker, :attempt])
    Honeybadger.notify(meta.reason, metadata: context, stacktrace: meta.stacktrace)
  end

  def handle_event([:oban, :job, :exception], _measurements, _meta, _config), do: :ok
end
