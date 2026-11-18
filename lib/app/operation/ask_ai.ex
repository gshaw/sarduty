defmodule App.Operation.AskAI do
  @moduledoc """
  One AI writing ask (docs/ai-writing.md). An admin describes a change; Claude
  rewrites the text, calling SAR Duty's tools to check it; SAR Duty checks the answer once
  more and gives it to the page, which fills the editor. Nothing is saved but the ask's
  row in `ai_asks`: the admin saves the report.

  Before Claude is called: AI writing is open to the user (App.Model.AISettings), the
  key is set, the team or organization has asks left today (not for a History line),
  and this month's
  asks cost less than the budget. The ask's row is written as it starts and its usage as
  each request returns, so Stop, which kills the ask's task, still counts what it spent.
  Each ask sends the text as it stands, with the job's earlier asks in its prompt. At
  most 6 requests per ask. A mistake in the answer goes back once, unseen; a second keeps
  the text as it was.

  `request/3`, `next_step/1`, and `usage/1` are pure, for tests. `call/4` runs the loop.
  """

  alias App.Accounts.User
  alias App.Adapter.Claude
  alias App.AI.Job
  alias App.AI.Models
  alias App.AI.Tool
  alias App.Model.AIAsk
  alias App.Model.AISettings
  alias App.Model.Organization
  alias App.Model.Team

  require Logger

  @max_requests 6
  @asks_per_day 100
  @max_tokens 16_000

  def asks_per_day, do: @asks_per_day

  @doc """
  Whether `user` can ask for `owner`, a team or an organization (an organization's
  form, #1089), now: `:ok`, or `{:error, reason}` with reason `:off` (not open to them,
  or no key here), `:daily_limit`, or `:paused` (the budget is spent). Each owner has
  its own daily limit. `kind` is the job's: a `:history_line` skips the daily limit.
  """
  def check(owner, %User{} = user, now, kind \\ :report)
      when is_struct(owner, Team) or is_struct(owner, Organization),
      do: check(owner, user, now, kind, AISettings.get())

  defp check(owner, user, now, kind, settings) do
    cond do
      not (Claude.configured?() and AISettings.open_to?(settings, user)) ->
        {:error, :off}

      kind != :history_line and AIAsk.count_today(owner, now) >= @asks_per_day ->
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
  `:refused`, `:too_many_steps` (#{@max_requests} requests without an answer), `:too_long`
  (cut off at max tokens), `:failed`, or `{:checks, mistake}`.
  """
  def call(owner, %User{} = user, %Job{} = job, now)
      when is_struct(owner, Team) or is_struct(owner, Organization) do
    settings = AISettings.get()

    job = %{job | suggest: AISettings.suggest?(settings, job.kind)}

    with :ok <- check(owner, user, now, job.kind, settings) do
      history = [%{"role" => "user", "content" => job.prompt}]

      row =
        AIAsk.record!(
          AIAsk.owner(owner) ++
            [
              user_id: user.id,
              kind: job.kind,
              ask: job.ask,
              model: settings.model,
              outcome: :stopped,
              duration_ms: 0,
              asked_at: now
            ]
        )

      acc = %{
        usage: %{input: 0, cache_write: 0, cache_read: 0, output: 0},
        requests: 0,
        row: row,
        started: System.monotonic_time(:millisecond)
      }

      {result, acc} = loop(settings, job, history, acc, false)
      AIAsk.update!(acc.row, outcome: outcome(result), duration_ms: took(acc))
      result
    end
  end

  defp took(acc), do: System.monotonic_time(:millisecond) - acc.started

  # Each response's usage goes on the row as it returns.
  defp count(acc, response, settings) do
    usage = add(acc.usage, usage(response))
    requests = acc.requests + 1

    row =
      AIAsk.update!(acc.row,
        input_tokens: usage.input,
        cache_write_tokens: usage.cache_write,
        cache_read_tokens: usage.cache_read,
        output_tokens: usage.output,
        cost_microdollars: Models.cost_microdollars(settings.model, usage),
        turns: requests,
        duration_ms: took(acc)
      )

    %{acc | usage: usage, requests: requests, row: row}
  end

  # `history` is the conversation so far, newest first.
  defp loop(_settings, _job, _history, %{requests: n} = acc, _retried)
       when n >= @max_requests,
       do: {{:error, :too_many_steps}, acc}

  defp loop(settings, job, history, acc, retried) do
    case settings
         |> request(job, Enum.reverse(history))
         |> Claude.create_message(stream: job.stream) do
      {:ok, response} ->
        acc = count(acc, response, settings)
        history = [%{"role" => "assistant", "content" => response["content"]} | history]
        answer(next_step(response), settings, job, history, acc, retried)

      {:error, reason} ->
        {{:error, reason}, acc}
    end
  end

  defp answer({:tools, uses}, settings, job, history, acc, retried) do
    results = Enum.map(uses, &run_tool(&1, job))
    loop(settings, job, [%{"role" => "user", "content" => results} | history], acc, retried)
  end

  defp answer({:answer, output}, settings, job, history, acc, retried) do
    case job.finish.(output) do
      {:retry, mistake} when not retried ->
        again = "SAR Duty's check found a mistake: #{mistake} Fix it and answer again."

        loop(
          settings,
          job,
          [%{"role" => "user", "content" => again} | history],
          acc,
          true
        )

      {:retry, mistake} ->
        {{:error, {:checks, mistake}}, acc}

      result ->
        {with_next(result, job, output), acc}
    end
  end

  defp answer(error, _settings, _job, _history, acc, _retried), do: {error, acc}

  # With suggestions on, the next asks AI gave: `result.next`, or a third element after
  # an unchanged ask's note.
  defp with_next(result, %Job{suggest: false}, _output), do: result
  defp with_next({:ok, result}, _job, output), do: {:ok, Map.put(result, :next, next(output))}
  defp with_next({:unchanged, note}, _job, output), do: {:unchanged, note, next(output)}
  defp with_next(result, _job, _output), do: result

  @doc "Up to two short next asks from an answer's `next`, each trimmed: two fit on one line in the column."
  def next(%{"next" => list}) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.length(&1) > 80))
    |> Enum.uniq()
    |> Enum.take(2)
  end

  def next(_output), do: []

  @next %{
    "type" => "array",
    "items" => %{"type" => "string"},
    "description" =>
      "One or two short asks the admin might try next, a few words each in their own " <>
        "voice, such as \"Group by quarter\". Only what SAR Duty can do. None when " <>
        "nothing more would help."
  }

  defp run_tool(%{"id" => id, "name" => name, "input" => input}, job) do
    result =
      case Enum.find(job.tools, &(&1.name() == name)) do
        nil ->
          {:error, "There is no tool #{name}."}

        tool ->
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
  (adaptive on every model listed) at the job's effort. A job with no tools sends none.
  """
  def request(%AISettings{} = settings, %Job{} = job, messages) do
    %{
      "model" => settings.model,
      "max_tokens" => @max_tokens,
      "inference_geo" => "us",
      "output_config" => %{
        "effort" => job.effort,
        "format" => %{"type" => "json_schema", "schema" => schema(job)}
      },
      "system" =>
        Enum.map(
          job.system,
          &%{"type" => "text", "text" => &1, "cache_control" => %{"type" => "ephemeral"}}
        ),
      "messages" => messages
    }
    |> put_tools(job.tools)
  end

  defp schema(%Job{suggest: false, schema: schema}), do: schema

  defp schema(%Job{schema: schema}) do
    schema
    |> Map.update("properties", %{"next" => @next}, &Map.put(&1, "next", @next))
    |> Map.update("required", ["next"], &["next" | &1])
  end

  defp put_tools(request, []), do: request

  defp put_tools(request, tools),
    do: Map.put(request, "tools", Enum.map(tools, &Tool.definition/1))

  @doc """
  What a response asks for next: `{:tools, uses}`, `{:answer, map}`, or
  `{:error, :refused | :too_long | :failed}`.
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
  def next_step(%{"stop_reason" => "max_tokens"}), do: {:error, :too_long}
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
  defp outcome({:unchanged, _note, _next}), do: :unchanged
  defp outcome({:error, {:checks, _mistake}}), do: :refused_by_checks
  defp outcome({:error, :refused}), do: :refused
  defp outcome({:error, _reason}), do: :failed
end
