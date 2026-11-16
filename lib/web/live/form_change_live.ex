defmodule Web.FormChangeLive do
  use Web, :live_view_app_layout

  import Web.Components.AIWriting

  alias App.AI.FormJob
  alias App.Model.Form
  alias App.Model.Team
  alias App.Operation.AskAI
  alias App.Operation.SaveForm
  alias App.Operation.TryForm
  alias Web.FormOwner

  # Change form (#1089): a team admin writes the team's form with AI writing
  # (docs/ai-writing.md#forms), as the report editor does. The form tried on one of the
  # team's activities, marked SAMPLE, as Try it prints it, is the main column; AI writing
  # is the column beside it. Each ask runs in `start_async` (App.Operation.AskAI, with
  # App.AI.FormJob) with the visit's earlier asks and replies, and its text replaces the
  # draft, so the try reprints here, in SAR Duty, after Claude is done. Undo puts back
  # the text from before an ask and drops the asks after it. The text is folded and read
  # only: the box is the one way to change it here.
  #
  # New form's Write form opens it with its first ask, What it's for, in the flash, so a
  # reload never asks again. Nothing is saved until Save form, which keeps the form's
  # state; a reload loses the conversation.
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user} = socket.assigns
    team = team!(socket.assigns)
    form = Form.get(team, id) || raise(Web.Status.NotFound)
    first = Phoenix.Flash.get(socket.assigns.flash, :ai_ask)

    socket
    |> clear_first_ask()
    |> assign(
      page_title: "Change form",
      team: team,
      form: form,
      page: Form.page_bytes(form),
      text: form.text,
      text_open: false,
      activity: nil,
      activities: [],
      pages: [],
      preview_error: nil
    )
    |> assign_ai(team, user)
    |> preview()
    |> first_ask(first)
    |> then(&{:ok, &1})
  end

  # A team's form, for its team admins and SAR Duty admins.
  defp team!(%{current_user: user} = assigns) do
    case FormOwner.get(assigns) do
      %Team{} = team ->
        if SaveForm.allowed?(team, user), do: team, else: raise(Web.Status.NotFound)

      _organization ->
        raise(Web.Status.NotFound)
    end
  end

  # The first ask stays in the flash until the page is live, which starts it.
  defp clear_first_ask(socket),
    do: if(connected?(socket), do: clear_flash(socket, :ai_ask), else: socket)

  defp assign_ai(socket, team, user) do
    assign(socket,
      ai: AskAI.check(team, user, DateTime.utc_now(), :form),
      ai_form: ask_form(""),
      ai_pending: nil,
      ai_asks: []
    )
  end

  # Write form's first ask, once the page is live.
  defp first_ask(socket, ask) when is_binary(ask) do
    if connected?(socket) and socket.assigns.ai == :ok,
      do: start_ask(socket, ask),
      else: socket
  end

  defp first_ask(socket, _none), do: socket

  # The draft tried on an activity it shows on, every page a picture; before it's
  # written, the agency's blank page. It prints beside the page, so a pick or an Undo
  # answers at once; a newer print replaces one still running.
  defp preview(socket) do
    %{form: form, text: text, team: team, page: page, activity: activity} = socket.assigns
    draft = %{form | text: text}
    activity_id = activity && activity.id

    socket
    |> assign(previewing: true)
    |> start_async(:preview, fn -> print(draft, team, page, activity_id) end)
  end

  defp print(draft, team, page, activity_id) do
    cond do
      Form.written?(draft) -> try_draft(draft, team, activity_id)
      page -> Map.merge(%{activities: [], activity: nil}, pages(page))
      true -> %{activities: [], activity: nil, pages: [], preview_error: nil}
    end
  end

  defp try_draft(draft, team, activity_id) do
    activities = TryForm.activities(draft, team)
    activity = Enum.find(activities, &(&1.id == activity_id)) || TryForm.first(activities)

    printed =
      case activity && TryForm.call(draft, team, activity.id) do
        nil -> %{pages: [], preview_error: nil}
        {:ok, attachment} -> pages(attachment.content)
        {:error, reason} -> %{pages: [], preview_error: reason}
      end

    Map.merge(%{activities: activities, activity: activity}, printed)
  end

  defp pages(pdf) do
    case Service.PDFImages.pages(pdf) do
      {:ok, pages} -> %{pages: pages, preview_error: nil}
      {:error, reason} -> %{pages: [], preview_error: reason}
    end
  end

  def handle_event("try_on", %{"activity" => id}, socket) do
    activity = Enum.find(socket.assigns.activities, &(to_string(&1.id) == id))
    {:noreply, socket |> assign(activity: activity) |> preview()}
  end

  def handle_event("show_text", _params, socket), do: {:noreply, assign(socket, text_open: true)}
  def handle_event("hide_text", _params, socket), do: {:noreply, assign(socket, text_open: false)}

  def handle_event("ask", %{"ai" => %{"ask" => ask}}, socket) do
    case String.trim(ask) do
      "" -> {:noreply, socket}
      _ask when socket.assigns.ai_pending != nil -> {:noreply, socket}
      ask -> {:noreply, start_ask(socket, ask)}
    end
  end

  def handle_event("cancel_ask", _params, socket) do
    pending = socket.assigns.ai_pending

    {:noreply,
     socket
     |> cancel_async(:ai_ask)
     |> assign(ai_pending: nil, ai_form: ask_form((pending && pending.ask) || ""))
     |> put_flash(:info, "Stopped. Nothing changed.")}
  end

  def handle_event("undo_ask", %{"id" => id}, socket) do
    case Enum.split_while(socket.assigns.ai_asks, &(to_string(&1.id) != id)) do
      {_newer, [ask | older]} ->
        {:noreply,
         socket
         |> assign(text: ask.before, ai_asks: older)
         |> preview()
         |> put_flash(:info, "Undone. The form is back to before that ask.")}

      {_all, []} ->
        {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    %{team: team, form: form, text: text, current_user: user} = socket.assigns

    if text == form.text do
      {:noreply,
       socket
       |> put_flash(:info, "Nothing to save. #{form.name} is as it was.")
       |> push_navigate(to: FormOwner.form_path(team, form))}
    else
      save(socket, team, form, text, user)
    end
  end

  defp save(socket, team, form, text, user) do
    case SaveForm.call(team, form, text, nil, user) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{saved.name} saved. It's version #{saved.version}.")
         |> push_navigate(to: FormOwner.form_path(team, saved))}

      {:error, _field, message} ->
        {:noreply, put_flash(socket, :error, "The form did not save. #{message}")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer change this team's forms.")}
    end
  end

  def handle_async(:preview, {:ok, printed}, socket),
    do: {:noreply, socket |> assign(printed) |> assign(previewing: false)}

  def handle_async(:preview, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_async(:ai_ask, {:ok, result}, socket) do
    {:noreply, socket |> ask_done(result) |> assign(ai_pending: nil) |> refresh_ai()}
  end

  # Stop already put the words back.
  def handle_async(:ai_ask, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:ai_ask, {:exit, _reason}, socket) do
    {:noreply, socket |> ask_done({:error, :unreachable}) |> assign(ai_pending: nil)}
  end

  # The ask runs beside the page, with the visit's earlier asks.
  defp start_ask(socket, ask) do
    %{team: team, form: form, page: page, text: text, ai_asks: asks, current_user: user} =
      socket.assigns

    earlier = asks |> Enum.reverse() |> Enum.map(&Map.take(&1, [:ask, :note, :blank]))
    now = DateTime.utc_now()

    socket
    |> assign(ai_pending: %{ask: ask, before: text}, ai_form: ask_form(""))
    |> start_async(:ai_ask, fn ->
      job = FormJob.build(team, form, page, text, ask, now, earlier)
      AskAI.call(team, user, job, now)
    end)
  end

  defp ask_done(socket, {:ok, %{text: text, note: note, blank: blank}}) do
    socket
    |> assign(text: text)
    |> preview()
    |> add_ask(blank_or(note, nil), true, blank)
  end

  defp ask_done(socket, {:unchanged, note}),
    do: add_ask(socket, blank_or(note, "Nothing changed."), false, [])

  # A failed ask leaves no reply: a toast says why, and its words go back in the box.
  defp ask_done(socket, {:error, reason}) do
    socket
    |> assign(ai_form: ask_form(socket.assigns.ai_pending.ask))
    |> put_flash(:error, ai_error_text(reason))
  end

  # The conversation, newest first. `undo?` is false for an ask that changed nothing.
  defp add_ask(socket, note, undo?, blank) do
    pending = socket.assigns.ai_pending

    entry = %{
      id: System.unique_integer([:positive]),
      ask: pending.ask,
      before: pending.before,
      note: note,
      undo?: undo?,
      blank: blank
    }

    assign(socket, ai_asks: [entry | socket.assigns.ai_asks])
  end

  defp refresh_ai(socket) do
    %{team: team, current_user: user} = socket.assigns
    assign(socket, ai: AskAI.check(team, user, DateTime.utc_now(), :form))
  end

  defp ai_error_text(:daily_limit),
    do: "Your team has used today's #{AskAI.asks_per_day()} asks. Ask again tomorrow."

  defp ai_error_text(reason) when reason in [:paused, :no_credit],
    do: "AI writing is paused until next month."

  defp ai_error_text(:busy), do: "AI writing is busy. Try again in a minute."
  defp ai_error_text(:refused), do: "AI writing cannot help with that. Try other words."

  defp ai_error_text({:checks, mistake}),
    do: "Its text still had a mistake: #{mistake} Ask again in other words."

  defp ai_error_text(:off), do: "AI writing is off."
  defp ai_error_text(_reason), do: "AI writing did not answer. Try again."

  defp ai_closed_text(:ok), do: nil
  defp ai_closed_text({:error, reason}), do: ai_error_text(reason)

  defp blank_or(value, default) do
    case String.trim(value || "") do
      "" -> default
      text -> text
    end
  end

  # The draft's name, once its text says one.
  defp title(form, text) do
    case App.Document.parse(text || "") do
      {:ok, %{name: name}} when is_binary(name) and name != "" -> name
      _none -> form.name
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={FormOwner.settings_path(@team)} />
      <:item label="Forms" path={FormOwner.forms_path(@team)} />
      <:item label={@form.name} path={FormOwner.form_path(@team, @form)} />
      <:item label="Change form" />
    </.breadcrumbs>
    <.heading_row>
      <h1 id="form-title" class="title">{title(@form, @text)}</h1>
      <:action>
        <.button id="form-save" variant={:success} phx-click="save" phx-disable-with="Saving…">
          Save form
        </.button>
        <.button id="form-cancel" navigate={FormOwner.form_path(@team, @form)}>Cancel</.button>
      </:action>
    </.heading_row>

    <.ai_editor id="form-editor" ai?={true} column_id="form-ai">
      <:column>
        <.ai_writing
          id="form-ai"
          ai={@ai}
          form={@ai_form}
          pending={@ai_pending}
          asks={@ai_asks}
          label="Ask AI"
          button="Ask"
          closed={ai_closed_text(@ai)}
          sees="AI works only with the agency's blank form, the form language, and your team's field names. Agents never see your team's members or records."
        >
          A change, or a question about the form.
        </.ai_writing>
      </:column>

      <section id="form-try" class="mb-8">
        <form
          :if={@activities != []}
          id="form-try-form"
          phx-change="try_on"
          phx-submit="try_on"
          class="measure"
        >
          <.input
            id="form-try-activity"
            name="activity"
            type="select"
            label="Tried on"
            value={@activity && @activity.id}
            options={Enum.map(@activities, &{activity_label(&1, @team), &1.id})}
          >
            Marked SAMPLE, with each question's default answer.
          </.input>
        </form>
        <p
          :if={written?(@text) and @activities == [] and !@previewing}
          id="form-try-none"
          class="measure"
        >
          Your team has no activity this form shows on.
        </p>
        <p :if={!written?(@text)} id="form-blank-page" class="measure">
          The agency's blank form. AI writes the form from it.
        </p>
        <p :if={@previewing} id="form-try-printing" class="hint mb-3">
          <.spinner>Printing it…</.spinner>
        </p>
        <p :if={@preview_error} id="form-try-error" class="measure">{@preview_error}</p>
        <div :if={@pages != []} id="form-pages" class="flex flex-col gap-4">
          <img
            :for={{png, n} <- Enum.with_index(@pages, 1)}
            id={"form-page-#{n}"}
            src={"data:image/png;base64," <> Base.encode64(png)}
            alt={page_alt(n, length(@pages), @text)}
            class="w-full border border-border-subtle shadow-sm"
          />
        </div>
      </section>

      <section :if={written?(@text)} id="form-text">
        <p class="action mb-3">
          <.a :if={!@text_open} id="form-show-text" href="#" phx-click="show_text">Show text</.a>
          <.a :if={@text_open} id="form-hide-text" href="#" phx-click="hide_text">Hide text</.a>
        </p>
        <p class="hint measure">
          The form in SAR Duty's form language, read only. Ask AI to change it.
        </p>
        <pre :if={@text_open} id="form-text-code" class="code-block mt-3"><code>{@text}</code></pre>
      </section>
    </.ai_editor>
    """
  end

  defp written?(text), do: String.trim(text || "") != ""

  defp page_alt(n, count, text) do
    if written?(text),
      do: "Page #{n} of #{count}, marked SAMPLE",
      else: "Page #{n} of #{count} of the agency's blank form"
  end

  defp activity_label(activity, team),
    do: "#{activity.title}, #{Service.Format.date_short(activity.started_at, team.timezone)}"
end
