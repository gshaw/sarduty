defmodule App.Operation.AskAI do
  @moduledoc """
  One AI writing ask (docs/ai-writing.md). A team admin describes a change; Claude
  rewrites the text, calling SAR Duty's tools to check it; SAR Duty checks the answer once
  more and gives it to the page, which fills the editor. Nothing is saved but the ask's
  row in `ai_asks`: the admin saves the report.

  Before Claude is called: AI writing is open to the user (App.Model.AISettings), the
  key is set, the team has asks left today, and this month's asks cost less than the
  budget. Each ask starts fresh, with the text as it stands: no conversation is kept.
  At most 6 requests per ask. A mistake in the answer goes back once, unseen; a second
  keeps the text as it was.

  `request/3`, `next_step/1`, and `usage/1` are pure, for tests. `call/5` runs the loop.
  """

  alias App.Accounts.User
  alias App.Adapter.Claude
  alias App.AI.Job
  alias App.AI.Models
  alias App.AI.Tool
  alias App.Model.AIAsk
  alias App.Model.AISettings
  alias App.Model.Team

  require Logger

  @max_requests 6
  @asks_per_day 100
  @max_tokens 16_000

  def asks_per_day, do: @asks_per_day

  @doc """
  Whether `user` can ask on `team` now: `:ok`, or `{:error, reason}` with reason `:off`
  (not open to them, or no key here), `:daily_limit`, or `:paused` (the budget is spent).
  """
  def check(%Team{} = team, %User{} = user, now, settings \\ AISettings.get()) do
    cond do
      not (Claude.configured?() and AISettings.open_to?(settings, user)) ->
        {:error, :off}

      AIAsk.count_today(team, now) >= @asks_per_day ->
        {:error, :daily_limit}

      AIAsk.month_cost_microdollars(now) >= settings.monthly_budget_cents * 10_000 ->
        {:error, :paused}

      true ->
        :ok
    end
  end

  @doc """
  Runs the ask. `{:ok, result}` from the job's `finish`, `{:unchanged, note}`, or
  `{:error, reason}`: those of `check/4`, `:no_credit`, `:busy`, `:unreachable`,
  `:refused`, `:failed`, or `{:checks, mistake}`. `opts[:on_step]` is called with
  `:writing`, `:checking`, or `:trying` as the ask goes.
  """
  def call(%Team{} = team, %User{} = user, %Job{} = job, now, opts \\ []) do
    settings = AISettings.get()

    with :ok <- check(team, user, now, settings) do
      started = System.monotonic_time(:millisecond)
      on_step = Keyword.get(opts, :on_step, fn _step -> :ok end)
      history = [%{"role" => "user", "content" => job.prompt}]
      acc = %{usage: %{input: 0, cache_write: 0, cache_read: 0, output: 0}, requests: 0}

      {result, acc} = loop(settings, job, history, acc, false, on_step)

      AIAsk.record!(
        team_id: team.id,
        user_id: user.id,
        kind: job.kind,
        ask: job.ask,
        model: settings.model,
        input_tokens: acc.usage.input,
        cache_write_tokens: acc.usage.cache_write,
        cache_read_tokens: acc.usage.cache_read,
        output_tokens: acc.usage.output,
        cost_microdollars: Models.cost_microdollars(settings.model, acc.usage),
        turns: acc.requests,
        duration_ms: System.monotonic_time(:millisecond) - started,
        outcome: outcome(result),
        asked_at: now
      )

      result
    end
  end

  # `history` is the conversation so far, newest first.
  defp loop(_settings, _job, _history, %{requests: n} = acc, _retried, _on_step)
       when n >= @max_requests,
       do: {{:error, :failed}, acc}

  defp loop(settings, job, history, acc, retried, on_step) do
    on_step.(:writing)

    case settings |> request(job, Enum.reverse(history)) |> Claude.create_message() do
      {:ok, response} ->
        acc = %{acc | usage: add(acc.usage, usage(response)), requests: acc.requests + 1}
        history = [%{"role" => "assistant", "content" => response["content"]} | history]
        answer(next_step(response), settings, job, history, acc, retried, on_step)

      {:error, reason} ->
        {{:error, reason}, acc}
    end
  end

  defp answer({:tools, uses}, settings, job, history, acc, retried, on_step) do
    results = Enum.map(uses, &run_tool(&1, job, on_step))

    loop(
      settings,
      job,
      [%{"role" => "user", "content" => results} | history],
      acc,
      retried,
      on_step
    )
  end

  defp answer({:answer, output}, settings, job, history, acc, retried, on_step) do
    case job.finish.(output) do
      {:retry, mistake} when not retried ->
        on_step.(:checking)
        again = "SAR Duty's check found a mistake: #{mistake} Fix it and answer again."

        loop(
          settings,
          job,
          [%{"role" => "user", "content" => again} | history],
          acc,
          true,
          on_step
        )

      {:retry, mistake} ->
        {{:error, {:checks, mistake}}, acc}

      result ->
        {result, acc}
    end
  end

  defp answer(error, _settings, _job, _history, acc, _retried, _on_step), do: {error, acc}

  defp run_tool(%{"id" => id, "name" => name, "input" => input}, job, on_step) do
    result =
      case Enum.find(job.tools, &(&1.name() == name)) do
        nil ->
          {:error, "There is no tool #{name}."}

        tool ->
          step = if name == "try_report", do: :trying, else: :checking
          on_step.(step)
          args = if is_map(input), do: input, else: %{}
          call_tool(tool, job.context, args)
      end

    case result do
      {:ok, output} ->
        %{"type" => "tool_result", "tool_use_id" => id, "content" => Jason.encode!(output)}

      {:error, message} ->
        %{"type" => "tool_result", "tool_use_id" => id, "content" => message, "is_error" => true}
    end
  end

  # A tool that raises fails its call, not the ask: Claude hears it failed and goes on
  # without it, and the error still reaches Honeybadger through the log.
  defp call_tool(tool, context, args) do
    tool.call(context, args)
  rescue
    exception ->
      :error |> Exception.format(exception, __STACKTRACE__) |> Logger.error()
      {:error, "#{tool.name()} failed in SAR Duty. Go on without it."}
  end

  @doc """
  The Messages API request for `job` on `settings`' model, with `messages` so far. Runs
  in the US. Every system part is a cache breakpoint. Thinking is left to the model
  (adaptive on every model listed) at effort medium.
  """
  def request(%AISettings{} = settings, %Job{} = job, messages) do
    %{
      "model" => settings.model,
      "max_tokens" => @max_tokens,
      "inference_geo" => "us",
      "output_config" => %{
        "effort" => "medium",
        "format" => %{"type" => "json_schema", "schema" => job.schema}
      },
      "system" =>
        Enum.map(
          job.system,
          &%{"type" => "text", "text" => &1, "cache_control" => %{"type" => "ephemeral"}}
        ),
      "tools" => Enum.map(job.tools, &Tool.definition/1),
      "messages" => messages
    }
  end

  @doc """
  What a response asks for next: `{:tools, uses}`, `{:answer, map}`, or
  `{:error, :refused | :failed}`.
  """
  def next_step(%{"stop_reason" => "tool_use", "content" => content}) do
    case Enum.filter(content, &(&1["type"] == "tool_use")) do
      [] -> {:error, :failed}
      uses -> {:tools, uses}
    end
  end

  def next_step(%{"stop_reason" => "end_turn", "content" => content}) do
    text = content |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join(& &1["text"])

    case Jason.decode(text) do
      {:ok, output} when is_map(output) -> {:answer, output}
      _not_json -> {:error, :failed}
    end
  end

  def next_step(%{"stop_reason" => "refusal"}), do: {:error, :refused}
  def next_step(_response), do: {:error, :failed}

  @doc "A response's token counts."
  def usage(%{"usage" => usage}) when is_map(usage) do
    %{
      input: usage["input_tokens"] || 0,
      cache_write: usage["cache_creation_input_tokens"] || 0,
      cache_read: usage["cache_read_input_tokens"] || 0,
      output: usage["output_tokens"] || 0
    }
  end

  def usage(_response), do: %{input: 0, cache_write: 0, cache_read: 0, output: 0}

  defp add(a, b), do: Map.merge(a, b, fn _key, x, y -> x + y end)

  defp outcome({:ok, _result}), do: :used
  defp outcome({:unchanged, _note}), do: :unchanged
  defp outcome({:error, {:checks, _mistake}}), do: :refused_by_checks
  defp outcome({:error, :refused}), do: :refused
  defp outcome({:error, _reason}), do: :failed
end
