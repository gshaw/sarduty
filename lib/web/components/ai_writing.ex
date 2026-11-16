defmodule Web.Components.AIWriting do
  @moduledoc """
  AI writing's column (docs/ai-writing.md), on Change report and Change form (#1089):
  what AI sees, then the asks as a conversation, oldest first, each with AI's reply and
  Undo when it changed the page; the running ask with Stop; Try next; and the box. Each
  page runs the asks (App.Operation.AskAI) and keeps the conversation; this draws it.

  `ai_editor` lays out the page: its head (the title, description, and links), the
  column, and its main part. From 1024px the column starts beside the title and stays in
  view as the page scrolls, filling the window down to the Save bar, and its
  conversation scrolls on its own (assets/js/ai_panel.js). Under that it's one column:
  the head, AI writing, then the main part, and the conversation shows its last two asks
  with Show earlier asks. Its CSS is assets/css/components/ai_writing.css, and
  /styles/ai-writing shows it.
  """
  use Web, :function_component

  import Web.Components.A

  alias Phoenix.LiveView.JS

  @doc """
  The page: its `head`, the AI writing column beside it when `ai?`, and its main part.
  """
  attr :id, :string, required: true
  attr :ai?, :boolean, required: true
  attr :label, :string, default: "AI writing"
  attr :column_id, :string, required: true
  slot :head, required: true
  slot :column, required: true
  slot :inner_block, required: true

  def ai_editor(assigns) do
    ~H"""
    <div id={@id} class={["ai-editor", @ai? && "has-ai"]}>
      <div class="ai-head">{render_slot(@head)}</div>
      <aside :if={@ai?} id={@column_id} class="ai-column" aria-label={@label} phx-hook="AIPanel">
        <h2 class="subheading mb-2">{@label}</h2>
        {render_slot(@column)}
      </aside>
      <div class="ai-main">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc """
  The bar stuck to the window's foot with Not saved yet and the page's Save and Cancel,
  its inner block. The AI writing column stops above it.
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
    <div class="ai-scroll">
      <p :if={@older > 0} class="action ai-earlier mb-3">
        <.a
          id={"#{@id}-earlier"}
          href="#"
          phx-click={JS.add_class("ai-thread-all", to: "##{@id}-asks") |> JS.hide()}
        >{Service.Format.count(@older, one: "Show %d earlier ask", many: "Show %d earlier asks")}</.a>
      </p>
      <ol :if={@pending || @asks != []} id={"#{@id}-asks"} class="ai-thread">
        <%= for {ask, n} <- @asks |> Enum.reverse() |> Enum.with_index() do %>
          <li id={"#{@id}-ask-#{ask.id}"} class={["ai-you", n < @older && "ai-older"]}>{ask.ask}</li>
          <li
            :if={ask.note || ask.undo? || blank(ask) != []}
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
    <div :if={@ai == :ok and !@pending and next(@asks) != []} id={"#{@id}-next"} class="mb-4">
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
        field_class="mb-1"
        phx-hook="AskEnter"
      >
        {render_slot(@inner_block)}
      </.input>
      <p class="hint ai-enter-hint mb-4">Enter sends it. Shift+Enter starts a new line.</p>
      <.button id={"#{@id}-ask"} variant={:success} disabled={@pending != nil}>{@button}</.button>
    </.form>
    <p :if={@ai != :ok} id={"#{@id}-closed"} class="hint">{@closed}</p>
    """
  end

  @doc """
  The box's form, holding `ask`. Each has its own id, so the box is a new element: a
  box still focused after its ask, as Safari leaves it, would otherwise keep its words.
  """
  def ask_form(ask),
    do: to_form(%{"ask" => ask}, as: "ai", id: "ai-#{System.unique_integer([:positive])}")

  defp blank(ask), do: Map.get(ask, :blank) || []

  # What AI suggests asking after the newest reply.
  defp next([newest | _older]), do: Map.get(newest, :next) || []
  defp next([]), do: []
end
