defmodule Web.Components.AIWriting do
  @moduledoc """
  AI writing's column (docs/ai-writing.md), on Change report and Change form (#1089):
  what AI sees, the asks as a conversation, oldest first, each with AI's reply and Undo
  when it changed the page, or what went wrong and Ask again when it failed, and the
  running ask with Stop last; then Try next and the box, as in a chat. Each page runs the asks
  (App.Operation.AskAI) and keeps the conversation; this draws it.

  `ai_editor` lays out the page: its head (the title, description, and links), the
  column, and its main part with the Save bar at its foot. From 1024px the column starts
  beside the title and sticks under the site bar. It grows as the conversation does, the
  box pushed down, until it's as tall as the window; then the conversation scrolls on
  its own, older asks off the top. Under that it's one column: the head, AI writing,
  then the main part, and the conversation shows its last two asks with Show earlier
  asks. Its CSS is assets/css/components/ai_writing.css, and /styles/ai-writing shows
  it.
  """
  use Web, :function_component

  import Web.Components.A

  alias App.Operation.AskAI
  alias Phoenix.LiveView.JS

  @doc """
  The page: its `head`, the AI writing column beside it when `ai?`, and its main part
  with `bar` at its foot: the Save bar (`save_bar`).
  """
  attr :id, :string, required: true
  attr :ai?, :boolean, required: true
  attr :label, :string, default: "AI writing"
  attr :column_id, :string, required: true
  slot :head, required: true
  slot :column, required: true
  slot :inner_block, required: true
  slot :bar

  def ai_editor(assigns) do
    ~H"""
    <div id={@id} class={["ai-editor", @ai? && "has-ai"]}>
      <div class="ai-head">{render_slot(@head)}</div>
      <aside :if={@ai?} id={@column_id} class="ai-column" aria-label={@label} phx-hook="AIPanel">
        <h2 class="subheading mb-2">{@label}</h2>
        {render_slot(@column)}
      </aside>
      <div class="ai-main">
        {render_slot(@inner_block)}
        {render_slot(@bar)}
      </div>
    </div>
    """
  end

  @doc """
  The bar under the main part with Not saved yet and the page's Save and Cancel, its
  inner block. It sticks to the window's foot while the main part runs past it, as the
  bar for checked rows does.
  """
  attr :id, :string, required: true
  slot :inner_block, required: true

  def save_bar(assigns) do
    ~H"""
    <div id={@id} class="action-bar ai-bar">{render_slot(@inner_block)}</div>
    """
  end

  @doc """
  The conversation, the box, and what AI sees. `id` starts each element's id, such as
  `report-ai`. `asks` is the conversation, newest first: each `%{id, ask, note, undo?}`
  and, for a form, `blank`, the labels AI left blank, `[%{label, why}]`, and `next`, the
  asks AI suggests after it: Try next shows the newest's, and a tap sends `suggest`
  with the ask, which the page puts in the box. `pending` is
  the running ask, `%{ask}`, shown as Thinking… with the seconds it has taken: one steady
  line, since an ask's own steps change too fast to read. `ai` is `:ok`, or why the box
  is closed, said by `closed`. Undo sends
  `undo_ask` with the ask's id, Stop `cancel_ask`, and the box `ask`.
  """
  attr :id, :string, required: true
  attr :ai, :any, required: true
  attr :form, :map, required: true
  attr :pending, :map, default: nil
  attr :asks, :list, required: true
  attr :label, :string, required: true
  attr :button, :string, required: true
  attr :closed, :string, default: nil
  attr :sees, :string, required: true
  slot :inner_block

  def ai_writing(assigns) do
    assigns = assign(assigns, :older, max(length(assigns.asks) - 2, 0))

    ~H"""
    <p class="hint mb-4">
      {@sees}
      <.a id={"#{@id}-agents-link"} href={~p"/agents"} external={true}>How it works</.a>
    </p>
    <div :if={@pending || @asks != []} class="ai-scroll">
      <p :if={@older > 0} class="action ai-earlier mb-3">
        <.a
          id={"#{@id}-earlier"}
          href="#"
          phx-click={JS.add_class("ai-thread-all", to: "##{@id}-asks") |> JS.hide()}
        >{Service.Format.count(@older, one: "Show %d earlier ask", many: "Show %d earlier asks")}</.a>
      </p>
      <ol id={"#{@id}-asks"} class="ai-thread">
        <%= for {ask, n} <- @asks |> Enum.reverse() |> Enum.with_index() do %>
          <li id={"#{@id}-ask-#{ask.id}"} class={["ai-you", n < @older && "ai-older"]}>{ask.ask}</li>
          <li
            :if={ask[:failed]}
            id={"#{@id}-reply-#{ask.id}"}
            class={["ai-reply ai-failed", n < @older && "ai-older"]}
          >
            <p class="font-semibold">{ask.failed.title}</p>
            <p>{ask.failed.detail}</p>
            <.button
              :if={ask.failed.again? and @ai == :ok and !@pending}
              id={"#{@id}-again-#{ask.id}"}
              type="button"
              size={:sm}
              phx-click="ask_again"
              phx-value-id={ask.id}
            >
              Ask again
            </.button>
          </li>
          <li
            :if={!ask[:failed] and (ask.note || ask.undo? || blank(ask) != [])}
            id={"#{@id}-reply-#{ask.id}"}
            class={["ai-reply", n < @older && "ai-older"]}
          >
            <p :if={ask.note}>{ask.note}</p>
            <div :if={blank(ask) != []} id={"#{@id}-blank-#{ask.id}"} class="ai-blank">
              <p class="font-semibold">Left blank</p>
              <ul>
                <li :for={item <- blank(ask)}>
                  <span class="font-semibold">{item.label}</span><span :if={item.why != ""}>: {item.why}</span>
                </li>
              </ul>
            </div>
            <.button
              :if={ask.undo?}
              id={"#{@id}-undo-#{ask.id}"}
              type="button"
              size={:sm}
              phx-click="undo_ask"
              phx-value-id={ask.id}
            >
              Undo
            </.button>
          </li>
        <% end %>
        <li :if={@pending} id={"#{@id}-ask-running"} class="ai-you">{@pending.ask}</li>
        <li :if={@pending} id={"#{@id}-step"} class="ai-step">
          <.spinner>
            Thinking… <span id={"#{@id}-seconds"} phx-hook="Seconds" phx-update="ignore"></span>
          </.spinner>
          <.button id={"#{@id}-stop"} type="button" size={:sm} phx-click="cancel_ask">
            Stop
          </.button>
        </li>
      </ol>
    </div>
    <div :if={@ai == :ok and !@pending and next(@asks) != []} id={"#{@id}-next"} class="ai-next">
      <p class="hint mb-2">Try next</p>
      <div class="flex flex-wrap gap-2">
        <.button
          :for={{ask, n} <- Enum.with_index(next(@asks))}
          id={"#{@id}-next-#{n}"}
          type="button"
          size={:sm}
          phx-click="suggest"
          phx-value-ask={ask}
        >{ask}</.button>
      </div>
    </div>
    <.form :if={@ai == :ok} for={@form} id={"#{@id}-form"} class="ai-writing-form" phx-submit="ask">
      <.input
        field={@form[:ask]}
        type="textarea"
        rows="3"
        label={@label}
        field_class="mb-2"
        phx-hook="AskEnter"
      >
        {render_slot(@inner_block)}
      </.input>
      <div class="flex flex-wrap gap-2">
        <.button id={"#{@id}-ask"} variant={:success} disabled={@pending != nil}>{@button}</.button>
        <.button
          :if={test?()}
          id={"#{@id}-test"}
          name="test"
          value="1"
          disabled={@pending != nil}
        >
          Test
        </.button>
      </div>
    </.form>
    <p :if={@ai != :ok} id={"#{@id}-closed"} class="hint">{@closed}</p>
    """
  end

  @doc """
  Whether the box shows Test, beside Ask: only on a dev server. Test runs a made-up ask
  (`test_ask/3`) instead of asking Claude, so trying the column spends no credit.
  """
  def test?, do: Application.get_env(:sarduty, :dev_routes) == true

  @doc """
  The words of a Test ask: the box's, or "Test ask N" for an empty box.
  """
  def test_words(ask, asks), do: blank_or(String.trim(ask), "Test ask #{length(asks) + 1}")

  defp blank_or("", default), do: default
  defp blank_or(ask, _default), do: ask

  @doc """
  What an ask runs: `real`, or for Test (`test?`) a made-up answer, counting the visit's
  Test presses in the socket's `ai_tests`. Returns the socket and the function.
  """
  def ask_task(socket, test?, ask, real)
  def ask_task(socket, false, _ask, real), do: {socket, real}

  def ask_task(socket, true, ask, _real) do
    n = Map.get(socket.assigns, :ai_tests, 0)
    {assign(socket, ai_tests: n + 1), fn -> test_ask(ask, n) end}
  end

  @doc """
  A made-up answer for Test, after 1.5 seconds so Thinking… and Stop show. `n` counts the
  visit's Test presses from 0: every fourth fails with too many steps, and the rest change nothing and
  reply at a length that varies, with Try next. Never on production (`test?/0`).
  """
  def test_ask(ask, n) do
    Process.sleep(1_500)

    if rem(n, 4) == 3 do
      {:error, :too_many_steps}
    else
      line =
        "This is a test reply, with no call to AI. A real reply says what changed and why, " <>
          "or answers a question about the report."

      note = Enum.join(["You asked: #{ask}." | List.duplicate(line, rem(n, 3) * 2 + 1)], " ")
      {:unchanged, note, ["Group by month", "Add a total row", "Sort by name"]}
    end
  end

  @doc """
  The box's form, holding `ask`. Each has its own id, so the box is a new element: a
  box still focused after its ask, as Safari leaves it, would otherwise keep its words.
  """
  def ask_form(ask),
    do: to_form(%{"ask" => ask}, as: "ai", id: "ai-#{System.unique_integer([:positive])}")

  @doc """
  What a failed ask's reply says, for `reason` from App.Operation.AskAI: a `title`
  (what went wrong), a `detail` (what to try), and `again?`, whether Ask again could
  work. `thing` is what the admin can change by hand instead: "query" or "text".
  """
  def failed(reason, thing) do
    {title, detail, again?} = failed_words(reason, thing)
    %{title: title, detail: detail, again?: again?}
  end

  defp failed_words(:too_many_steps, _thing),
    do:
      {"AI took too many steps and stopped before it finished.",
       "Nothing changed. Ask for one change at a time.", true}

  defp failed_words(:too_long, _thing),
    do:
      {"AI's answer ran too long and was cut off.", "Nothing changed. Ask for a smaller change.",
       true}

  defp failed_words(:busy, _thing),
    do: {"AI is busy right now.", "Nothing changed. Ask again in a minute.", true}

  defp failed_words(:unreachable, _thing),
    do: {"SAR Duty could not reach AI.", "Nothing changed. Ask again in a minute.", true}

  defp failed_words(:refused, thing),
    do:
      {"AI won't help with that.",
       "Nothing changed. Try other words, or change the #{thing} yourself.", false}

  defp failed_words({:checks, mistake}, thing),
    do:
      {"AI's #{thing} still had a mistake after one fix.",
       "#{mistake} Nothing changed. Ask in other words, or fix the #{thing} yourself.", true}

  defp failed_words(:daily_limit, thing),
    do:
      {"Your team has used today's #{AskAI.asks_per_day()} asks.",
       "Ask again tomorrow, or change the #{thing} yourself.", false}

  defp failed_words(reason, thing) when reason in [:paused, :no_credit],
    do:
      {"AI writing is paused until next month.", "You can still change the #{thing} yourself.",
       false}

  defp failed_words(:off, thing),
    do: {"AI writing is off.", "You can still change the #{thing} yourself.", false}

  defp failed_words(_reason, _thing),
    do:
      {"AI's answer did not make sense to SAR Duty.",
       "Nothing changed. Ask again: the same words often work the second time.", true}

  defp blank(ask), do: Map.get(ask, :blank) || []

  # What AI suggests asking after the newest reply.
  defp next([newest | _older]), do: Map.get(newest, :next) || []
  defp next([]), do: []
end
