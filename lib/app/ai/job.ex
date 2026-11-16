defmodule App.AI.Job do
  @moduledoc """
  What one AI writing ask sends and how its answer is checked: built by a kind's module,
  such as App.AI.ReportJob, and run by App.Operation.AskAI.

  - `system`: the parts of the system prompt, stable ones first. Each part ends a cache
    breakpoint, so the shared text (the language) caches for every team and the team's
    own part for its next ask.
  - `tools`: App.AI.Tool modules Claude may call.
  - `prompt`: the user message, the current text and the ask: text, or content blocks
    such as a form's PDF.
  - `schema`: the JSON schema of the answer.
  - `finish`: takes the answer as a map and gives `{:ok, result}`, `{:unchanged, note}`,
    or `{:retry, mistake}`, which goes back to Claude once.
  - `context`: what tools get, `%{team:, now:}`, and what a kind's tools need more.
  - `ask`: the words kept on the `ai_asks` row.
  - `effort`: how hard the model thinks, `"medium"` unless the job is small.
  - `stream`: true streams each request under the hood, for a job whose answer may take
    near the adapter's timeout, such as a form's first draft (App.Adapter.Claude).
  """

  @enforce_keys [:kind, :system, :tools, :prompt, :schema, :finish, :context, :ask]
  defstruct [
    :kind,
    :system,
    :tools,
    :prompt,
    :schema,
    :finish,
    :context,
    :ask,
    effort: "medium",
    stream: false
  ]
end
