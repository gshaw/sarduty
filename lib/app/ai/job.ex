defmodule App.AI.Job do
  @moduledoc """
  What one AI writing ask sends and how its answer is checked: built by a kind's module,
  such as App.AI.ReportJob, and run by App.Operation.AskAI.

  - `system`: the parts of the system prompt, stable ones first. Each part ends a cache
    breakpoint, so the shared text (the language) caches for every team and the team's
    own part for its next ask.
  - `tools`: App.AI.Tool modules Claude may call.
  - `prompt`: the user message, the current text and the ask.
  - `schema`: the JSON schema of the answer.
  - `finish`: takes the answer as a map and gives `{:ok, result}`, `{:unchanged, note}`,
    or `{:retry, mistake}`, which goes back to Claude once.
  - `context`: what tools get, `%{team:, now:}`.
  """

  @enforce_keys [:kind, :system, :tools, :prompt, :schema, :finish, :context, :ask]
  defstruct @enforce_keys
end
