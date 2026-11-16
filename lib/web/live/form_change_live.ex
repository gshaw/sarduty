defmodule Web.FormChangeLive do
  use Web, :live_view_app_layout

  import Web.Components.AIWriting
  import Web.Components.FileDrop
  import Web.Components.PageActions

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
  # the text from before an ask and drops the asks after it. Two ways past AI writing sit
  # under the try: Show how it fills in opens the text for a small fix by hand, as Show
  # query does on a report, checked and tried as it's typed; Replace PDF, a dialog, takes
  # the agency's new PDF and asks AI to fit the form to it. Undo, Stop, or a failed ask
  # puts the old PDF back, and Save form saves both.
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
      text_error: nil,
      replacing: false,
      page_error: nil,
      activity: nil,
      activities: [],
      pages: [],
      preview_error: nil
    )
    |> allow_upload(:page, accept: ~w(.pdf), max_entries: 1, max_file_size: 10_000_000)
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
      Form.written?(draft) -> try_draft(draft, team, page, activity_id)
      page -> Map.merge(%{activities: [], activity: nil}, pages(page))
      true -> %{activities: [], activity: nil, pages: [], preview_error: nil}
    end
  end

  defp try_draft(draft, team, page, activity_id) do
    activities = TryForm.activities(draft, team)
    activity = Enum.find(activities, &(&1.id == activity_id)) || TryForm.first(activities)

    printed =
      case activity && TryForm.call(draft, team, activity.id, page: page) do
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

  @new_page_ask "Fit the form to the agency's new PDF."

  def handle_event("try_on", %{"activity" => id}, socket) do
    activity = Enum.find(socket.assigns.activities, &(to_string(&1.id) == id))
    {:noreply, socket |> assign(activity: activity) |> preview()}
  end

  def handle_event("validate_page", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :page, ref)}

  def handle_event("show_text", _params, socket), do: {:noreply, assign(socket, text_open: true)}
  def handle_event("hide_text", _params, socket), do: {:noreply, assign(socket, text_open: false)}

  # A fix by hand: checked as saving checks it, and tried again once it passes.
  def handle_event("edit_text", %{"text" => text}, socket) do
    %{team: team, form: form, page: page} = socket.assigns

    case SaveForm.check_for(team, form, text, page) do
      {:ok, _doc} -> {:noreply, socket |> assign(text: text, text_error: nil) |> preview()}
      {:error, _field, message} -> {:noreply, assign(socket, text: text, text_error: message)}
    end
  end

  def handle_event("open_replace", _params, socket),
    do: {:noreply, assign(socket, replacing: true, page_error: nil)}

  def handle_event("close_replace", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.page.entries, socket, &cancel_upload(&2, :page, &1.ref))

    {:noreply, assign(socket, replacing: false, page_error: nil)}
  end

  # The agency's new PDF takes the old one's place, and AI fits the form to it.
  def handle_event("replace_pdf", _params, socket) do
    bytes =
      consume_uploaded_entries(socket, :page, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case SaveForm.check_page(List.first(bytes)) do
      :ok when socket.assigns.ai_pending == nil ->
        old = socket.assigns.page

        {:noreply,
         socket
         |> assign(page: hd(bytes), replacing: false, page_error: nil)
         |> preview()
         |> start_ask(@new_page_ask, old)}

      :ok ->
        {:noreply, assign(socket, page_error: "Wait for AI to answer, then replace the PDF.")}

      {:error, :page, message} ->
        {:noreply, assign(socket, page_error: message)}
    end
  end

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
     |> put_back_page(pending)
     |> assign(ai_pending: nil, ai_form: ask_form((pending && pending.ask) || ""))
     |> put_flash(:info, "Stopped. Nothing changed.")}
  end

  def handle_event("undo_ask", %{"id" => id}, socket) do
    case Enum.split_while(socket.assigns.ai_asks, &(to_string(&1.id) != id)) do
      {_newer, [ask | older]} ->
        {:noreply,
         socket
         |> assign(text: ask.before, page: ask.before_page, ai_asks: older)
         |> preview()
         |> put_flash(:info, "Undone. The form is back to before that ask.")}

      {_all, []} ->
        {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    %{team: team, form: form, text: text, current_user: user} = socket.assigns

    page = if page_changed?(socket.assigns), do: socket.assigns.page

    if text == form.text and is_nil(page) do
      {:noreply,
       socket
       |> put_flash(:info, "Nothing to save. #{form.name} is as it was.")
       |> push_navigate(to: FormOwner.form_path(team, form))}
    else
      save(socket, team, form, text, page, user)
    end
  end

  defp page_changed?(%{form: form, page: page}), do: Form.sha256(page) != form.page_sha256

  defp save(socket, team, form, text, page, user) do
    case SaveForm.call(team, form, text, page, user) do
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

  # The ask runs beside the page, with the visit's earlier asks. `before_page` is the page
  # Undo puts back: the old one when the ask is for a new one.
  defp start_ask(socket, ask, before_page \\ nil) do
    %{team: team, form: form, page: page, text: text, ai_asks: asks, current_user: user} =
      socket.assigns

    earlier = asks |> Enum.reverse() |> Enum.map(&Map.take(&1, [:ask, :note, :blank]))
    now = DateTime.utc_now()

    socket
    |> assign(
      ai_pending: %{ask: ask, before: text, before_page: before_page || page},
      ai_form: ask_form("")
    )
    |> start_async(:ai_ask, fn ->
      job = FormJob.build(team, form, page, text, ask, now, earlier)
      AskAI.call(team, user, job, now)
    end)
  end

  defp ask_done(socket, {:ok, %{text: text, note: note, blank: blank}}) do
    socket
    |> assign(text: text, text_error: nil)
    |> preview()
    |> add_ask(blank_or(note, nil), true, blank)
  end

  defp ask_done(socket, {:unchanged, note}),
    do: add_ask(socket, blank_or(note, "Nothing changed."), false, [])

  # A failed ask leaves no reply: a toast says why, and its words go back in the box.
  defp ask_done(socket, {:error, reason}) do
    socket
    |> put_back_page(socket.assigns.ai_pending)
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
      before_page: pending.before_page,
      note: note,
      undo?: undo? or pending.before_page != socket.assigns.page,
      blank: blank
    }

    assign(socket, ai_asks: [entry | socket.assigns.ai_asks])
  end

  # Stop or a failed ask puts back the page from before it.
  defp put_back_page(socket, %{before_page: page}) when page != socket.assigns.page,
    do: socket |> assign(page: page) |> preview()

  defp put_back_page(socket, _pending), do: socket

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
        <%!-- The team's own activities; Open activity, at the label's end, checks the try
        against one in a new window. --%>
        <form
          :if={@activities != []}
          id="form-try-form"
          phx-change="try_on"
          phx-submit="try_on"
          class="measure"
        >
          <div class="flex items-baseline justify-between gap-4">
            <.label for="form-try-activity">Tried on</.label>
            <.a
              :if={@activity}
              id="form-try-open"
              href={~p"/teams/#{@team}/activities/#{@activity.id}"}
              external={true}
            >
              Open activity
            </.a>
          </div>
          <.input
            id="form-try-activity"
            name="activity"
            type="select"
            value={@activity && @activity.id}
            options={Enum.map(@activities, &{activity_label(&1, @team), &1.id})}
          />
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

      <section id="form-text">
        <.page_actions id="form-text-actions">
          <:action :if={!text_shown?(assigns)}>
            <.a id="form-show-text" href="#" phx-click="show_text">Show how it fills in</.a>
          </:action>
          <:action :if={text_shown?(assigns)}>
            <.a id="form-hide-text" href="#" phx-click="hide_text">Hide how it fills in</.a>
          </:action>
          <:action :if={@ai == :ok and is_nil(@ai_pending)}>
            <.a id="form-replace-pdf" href="#" phx-click="open_replace">Replace PDF</.a>
          </:action>
        </.page_actions>
        <p class="hint measure">
          AI writes the form. Show how it fills in for a small fix by hand, and Replace PDF
          when the agency puts out a new one.
        </p>
        <.form
          :if={text_shown?(assigns)}
          for={%{}}
          id="form-text-form"
          phx-change="edit_text"
          class="mt-6"
        >
          <.input
            id="form-text-input"
            name="text"
            type="textarea"
            label="How it fills in"
            value={@text}
            rows="16"
            class="font-mono"
            phx-debounce="500"
            spellcheck="false"
            errors={List.wrap(@text_error)}
          >
            What each value is, and where it goes on the page. For a small fix by hand.
          </.input>
        </.form>
      </section>
    </.ai_editor>

    <%!-- Replace PDF: the upload in a dialog over the page. Cancel or Escape closes it. --%>
    <dialog
      :if={@replacing}
      id="form-replace-dialog"
      class="confirm-dialog"
      phx-hook="AskDialog"
      phx-mounted={JS.ignore_attributes(["open"])}
      data-cancel-event="close_replace"
      aria-labelledby="form-replace-question"
    >
      <.form
        for={%{}}
        id="form-replace-form"
        phx-change="validate_page"
        phx-submit="replace_pdf"
      >
        <h2 id="form-replace-question" class="confirm-dialog-question">
          Replace the agency's PDF?
        </h2>
        <p>
          The agency's new PDF takes the old one's place, and AI fits the form to it. Nothing
          is saved until Save form, and Undo puts the old PDF back.
        </p>
        <div class="confirm-dialog-fields">
          <.file_drop
            id="form-replace-file"
            upload={@uploads.page}
            label="The agency's new PDF"
            kinds="a PDF"
            errors={List.wrap(@page_error)}
          >
            The blank form, as the agency gives it. A scan has no text to read.
          </.file_drop>
        </div>
        <div class="confirm-dialog-actions">
          <.button id="form-replace-save" variant={:success} phx-disable-with="Reading the PDF…">
            Replace PDF
          </.button>
          <.button id="form-replace-cancel" type="button" value="cancel" phx-click="close_replace">
            Cancel
          </.button>
        </div>
      </.form>
    </dialog>
    """
  end

  # The text shows while it's open, and while a fix by hand has a mistake.
  defp text_shown?(assigns), do: assigns.text_open or assigns.text_error != nil

  defp written?(text), do: String.trim(text || "") != ""

  defp page_alt(n, count, text) do
    if written?(text),
      do: "Page #{n} of #{count}, marked SAMPLE",
      else: "Page #{n} of #{count} of the agency's blank form"
  end

  defp activity_label(activity, team),
    do: "#{activity.title}, #{Service.Format.date_short(activity.started_at, team.timezone)}"
end
