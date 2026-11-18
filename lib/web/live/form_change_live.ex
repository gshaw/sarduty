defmodule Web.FormChangeLive do
  use Web, :live_view_app_layout

  import Web.Components.AIWriting
  import Web.Components.FileDrop
  import Web.Components.FormSample
  import Web.Components.PageActions
  import Web.Components.Unsaved

  alias App.AI.FormJob
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Operation.AskAI
  alias App.Operation.SaveDraft
  alias App.Operation.SaveForm
  alias Web.Components.FormSample
  alias Web.FormOwner
  alias Web.FormStartLive

  # Change form (#1089): an admin writes the form with AI writing
  # (docs/ai-writing.md#forms), as the report editor does, a team's form or an
  # organization's, one page for both (Web.FormOwner). The form tried on an activity, the
  # team's own or Coast Range SAR's for an organization, marked SAMPLE, drawn as the
  # form's page draws its Sample (Web.Components.FormSample), is the main column; AI
  # writing is the column beside it. Each ask runs in `start_async` (App.Operation.AskAI, with
  # App.AI.FormJob) with the visit's earlier asks and replies, and its text replaces the
  # draft, so the try reprints here, in SAR Duty, after Claude is done. Undo puts back
  # the text from before an ask and drops the asks after it. Two ways past AI writing sit
  # under the try: Show how it fills in opens the text for a small fix by hand, as Show
  # query does on a report, checked and tried as it's typed; Replace PDF, a dialog, takes
  # the agency's new PDF and asks AI to fit the form to it. Undo, Stop, or a failed ask
  # puts the old PDF back, and Save form saves both.
  #
  # New form's Write form opens it with its first ask, What it's for, in the flash, so a
  # reload never asks again. A form with no text, as after Stop or a failed ask, asks the
  # same in the box: What it's for and Write form, until it has text. Nothing
  # is saved until Save form, which keeps the form's state.
  #
  # Saved AI turns (#1089): after every ask and every fix by hand, the text, the PDF, and
  # the conversation are kept as the person's draft (App.Operation.SaveDraft), so the
  # page opens again as it was left, with a toast. Save form and Start over discard it;
  # Cancel leaves it for next time.
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user} = socket.assigns
    owner = owner!(socket.assigns)
    form = Form.get(owner, id) || raise(Web.Status.NotFound)
    first = Phoenix.Flash.get(socket.assigns.flash, :ai_ask)

    socket
    |> clear_first_ask()
    |> assign(
      page_title: "Change form",
      owner: owner,
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
    |> assign_ai(owner, user)
    |> open_draft(first)
    |> preview()
    |> first_ask(first)
    |> then(&{:ok, &1})
  end

  # For whoever saves the owner's forms (SaveForm.allowed?/3).
  defp owner!(%{current_user: user} = assigns) do
    owner = FormOwner.get(assigns)
    if SaveForm.allowed?(owner, user), do: owner, else: raise(Web.Status.NotFound)
  end

  # The first ask stays in the flash until the page is live, which starts it.
  defp clear_first_ask(socket),
    do: if(connected?(socket), do: clear_flash(socket, :ai_ask), else: socket)

  defp assign_ai(socket, owner, user) do
    assign(socket,
      ai: AskAI.check(owner, user, DateTime.utc_now(), :form),
      ai_form: ask_form(""),
      ai_pending: nil,
      ai_asks: []
    )
  end

  # The person's draft, as they left it, unless Write form's first ask opened the page.
  defp open_draft(socket, first) when is_binary(first), do: assign(socket, draft_at: nil, rev: 0)

  defp open_draft(socket, _first) do
    %{current_user: user, form: form, owner: owner} = socket.assigns

    case SaveDraft.open(user, form) do
      nil ->
        assign(socket, draft_at: nil, rev: 0)

      %{fields: fields, asks: asks, at: at} ->
        when_kept = Service.Format.day_at_time(at, DateTime.utc_now(), owner.timezone)

        socket
        |> assign(text: fields["text"], page: fields["page"], ai_asks: asks)
        |> assign(draft_at: at, rev: 0)
        |> put_flash(:info, "Your changes from #{when_kept} are back. Save form to keep them.")
    end
  end

  # Keeps the page as the person's draft, after an ask or a fix by hand.
  defp keep_draft(socket) do
    %{current_user: user, form: form, text: text, page: page, ai_asks: asks, rev: rev} =
      socket.assigns

    case SaveDraft.call(user, form, %{"text" => text, "page" => page}, asks) do
      {:ok, draft} ->
        assign(socket, draft_at: draft && draft.updated_at, rev: rev + 1)

      {:error, _reason} ->
        socket
        |> assign(draft_at: nil, rev: rev + 1)
        |> put_flash(:error, "Save form before you leave. SAR Duty could not keep your changes.")
    end
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
    %{form: form, text: text, owner: owner, page: page, activity: activity} = socket.assigns
    draft = %{form | text: text}
    activity_id = activity && activity.id

    socket
    |> assign(previewing: true)
    |> start_async(:preview, fn -> FormSample.print(draft, owner, page, activity_id) end)
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

  # A fix by hand: checked as saving checks it, beside the page, and tried again once it
  # passes. A newer check replaces one still running.
  def handle_event("edit_text", %{"text" => text}, socket) do
    %{owner: owner, form: form, page: page} = socket.assigns

    {:noreply,
     socket
     |> assign(text: text)
     |> keep_draft()
     |> start_async(:check_text, fn -> SaveForm.check_for(owner, form, text, page) end)}
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
    page =
      socket
      |> consume_uploaded_entries(:page, fn %{path: path}, _entry -> {:ok, File.read!(path)} end)
      |> List.first()

    case SaveForm.check_page(page) do
      :ok when socket.assigns.ai_pending == nil ->
        old = socket.assigns.page

        {:noreply,
         socket
         |> assign(page: page, replacing: false, page_error: nil)
         |> preview()
         |> start_ask(@new_page_ask, old)}

      :ok ->
        {:noreply, assign(socket, page_error: "Wait for AI to answer, then replace the PDF.")}

      {:error, :page, message} ->
        {:noreply, assign(socket, page_error: message)}
    end
  end

  def handle_event("ask", %{"ai" => %{"ask" => ask}, "test" => _test}, socket) do
    if test?() and socket.assigns.ai_pending == nil,
      do: {:noreply, start_ask(socket, test_words(ask, socket.assigns.ai_asks), nil, test: true)},
      else: {:noreply, socket}
  end

  def handle_event("ask", %{"ai" => %{"ask" => ask}}, socket) do
    cond do
      socket.assigns.ai_pending != nil ->
        {:noreply, socket}

      !written?(socket.assigns.text) ->
        {:noreply, start_ask(socket, FormStartLive.first_ask(ask))}

      String.trim(ask) == "" ->
        {:noreply, socket}

      true ->
        {:noreply, start_ask(socket, String.trim(ask))}
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

  # A suggested next ask goes in the box, to change or send.
  def handle_event("suggest", %{"ask" => ask}, socket),
    do: {:noreply, assign(socket, ai_form: ask_form(ask))}

  # A failed ask runs again in its place, on the PDF it ran on: a new PDF that failed to
  # fit goes back in, with the PDF before it for Undo.
  def handle_event("ask_again", %{"id" => id}, socket) do
    case Enum.split_with(socket.assigns.ai_asks, &(to_string(&1.id) == id and &1[:failed])) do
      {[failed], rest} when socket.assigns.ai_pending == nil ->
        {:noreply,
         socket
         |> assign(ai_asks: rest, page: failed.page)
         |> preview()
         |> start_ask(failed.ask, failed.before_page, test: failed.test?)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("undo_ask", %{"id" => id}, socket) do
    case Enum.split_while(socket.assigns.ai_asks, &(to_string(&1.id) != id)) do
      {_newer, [ask | older]} ->
        {:noreply,
         socket
         |> assign(text: ask.before, page: ask.before_page, ai_asks: older)
         |> keep_draft()
         |> preview()
         |> put_flash(:info, "Undone. The form is back to before that ask.")}

      {_all, []} ->
        {:noreply, socket}
    end
  end

  # Discards the draft and opens the page again on the saved version.
  def handle_event("start_over", _params, socket) do
    %{owner: owner, form: form, current_user: user} = socket.assigns
    SaveDraft.discard(user, form)

    {:noreply,
     socket
     |> put_flash(:info, "Started over. #{form.name} is as saved.")
     |> push_navigate(to: FormOwner.change_path(owner, form))}
  end

  def handle_event("save", _params, socket) do
    %{owner: owner, form: form, text: text, current_user: user} = socket.assigns

    page = if page_changed?(socket.assigns), do: socket.assigns.page

    if text == form.text and is_nil(page) do
      # Nothing to save, and nothing left to keep: a draft of questions alone goes too.
      SaveDraft.discard(user, form)

      {:noreply,
       socket
       |> put_flash(:info, "Nothing to save. #{form.name} is as it was.")
       |> push_navigate(to: FormOwner.form_path(owner, form))}
    else
      save(socket, owner, form, text, page, user)
    end
  end

  defp page_changed?(%{form: form, page: page}), do: Form.sha256(page) != form.page_sha256

  defp save(socket, owner, form, text, page, user) do
    case SaveForm.call(owner, form, text, page, user) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{saved.name} saved. It's version #{saved.version}.")
         |> push_navigate(to: FormOwner.form_path(owner, saved))}

      {:error, _field, message} ->
        {:noreply, put_flash(socket, :error, "The form did not save. #{message}")}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, "You can no longer change #{FormOwner.name(owner)}'s forms.")}
    end
  end

  def handle_async(:preview, {:ok, printed}, socket),
    do: {:noreply, socket |> assign(printed) |> assign(previewing: false)}

  def handle_async(:preview, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_async(:check_text, {:ok, {:ok, _doc}}, socket),
    do: {:noreply, socket |> assign(text_error: nil) |> preview()}

  def handle_async(:check_text, {:ok, {:error, _field, message}}, socket),
    do: {:noreply, assign(socket, text_error: message)}

  def handle_async(:check_text, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_async(:ai_ask, {:ok, result}, socket) do
    {:noreply,
     socket |> ask_done(result) |> assign(ai_pending: nil) |> keep_draft() |> refresh_ai()}
  end

  # Stop already put the words back.
  def handle_async(:ai_ask, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:ai_ask, {:exit, _reason}, socket) do
    {:noreply,
     socket |> ask_done({:error, :unreachable}) |> assign(ai_pending: nil) |> keep_draft()}
  end

  # The ask runs beside the page, with the visit's earlier asks. `before_page` is the page
  # Undo puts back: the old one when the ask is for a new one.
  # `test: true` is Test's made-up ask (AIWriting.test_ask/2), with no call to Claude.
  defp start_ask(socket, ask, before_page \\ nil, opts \\ []) do
    test? = Keyword.get(opts, :test, false)

    %{owner: owner, form: form, page: page, text: text, ai_asks: asks, current_user: user} =
      socket.assigns

    earlier = earlier(asks, [:ask, :note, :blank])
    now = DateTime.utc_now()

    {socket, test} = count_test(socket, test?)

    socket
    |> assign(
      ai_pending: %{ask: ask, before: text, before_page: before_page || page, test?: test?},
      ai_form: ask_form("")
    )
    |> start_async(:ai_ask, fn ->
      if test do
        test_ask(ask, test)
      else
        AskAI.call(owner, user, FormJob.build(owner, form, page, text, ask, now, earlier), now)
      end
    end)
  end

  defp ask_done(socket, {:ok, %{text: text, note: note, blank: blank} = result}) do
    socket
    |> assign(text: text, text_error: nil)
    |> preview()
    |> add_ask(blank_or(note, nil), true, blank, Map.get(result, :next, []))
  end

  defp ask_done(socket, {:unchanged, note}), do: ask_done(socket, {:unchanged, note, []})

  defp ask_done(socket, {:unchanged, note, next}),
    do: add_ask(socket, blank_or(note, "Nothing changed."), false, [], next)

  # A failed ask puts back the page from before it and stays in the conversation, saying
  # what went wrong, with Ask again. `page` is the PDF it ran on, for Ask again.
  defp ask_done(socket, {:error, reason}) do
    pending = socket.assigns.ai_pending

    entry = %{
      id: System.unique_integer([:positive]),
      ask: pending.ask,
      before: pending.before,
      before_page: pending.before_page,
      page: socket.assigns.page,
      test?: pending.test?,
      note: nil,
      undo?: false,
      blank: [],
      next: [],
      failed: failed(reason, "text")
    }

    socket
    |> put_back_page(pending)
    |> assign(ai_asks: [entry | socket.assigns.ai_asks])
  end

  # The conversation, newest first. `undo?` is false for an ask that changed nothing.
  defp add_ask(socket, note, undo?, blank, next) do
    pending = socket.assigns.ai_pending

    entry = %{
      id: System.unique_integer([:positive]),
      ask: pending.ask,
      before: pending.before,
      before_page: pending.before_page,
      note: note,
      undo?: undo? or pending.before_page != socket.assigns.page,
      blank: blank,
      next: next
    }

    assign(socket, ai_asks: [entry | socket.assigns.ai_asks])
  end

  # Stop or a failed ask puts back the page from before it.
  defp put_back_page(socket, %{before_page: page}) when page != socket.assigns.page,
    do: socket |> assign(page: page) |> preview()

  defp put_back_page(socket, _pending), do: socket

  defp refresh_ai(socket) do
    %{owner: owner, current_user: user} = socket.assigns
    assign(socket, ai: AskAI.check(owner, user, DateTime.utc_now(), :form))
  end

  defp ai_closed_text(:ok), do: nil

  defp ai_closed_text({:error, reason}) do
    %{title: title, detail: detail} = failed(reason, "text")
    "#{title} #{detail}"
  end

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
      <:item
        :if={FormOwner.settings_path(@owner)}
        label="Team settings"
        path={FormOwner.settings_path(@owner)}
      />
      <:item label="Forms" path={FormOwner.forms_path(@owner)} />
      <:item label={@form.name} path={FormOwner.form_path(@owner, @form)} />
      <:item label="Change form" />
    </.breadcrumbs>
    <.ai_editor id="form-editor" ai?={true} column_id="form-ai">
      <:head>
        <h1 id="form-title" class="title mb-2">{title(@form, @text)}</h1>
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
      </:head>
      <:column>
        <.ai_writing
          id="form-ai"
          ai={@ai}
          form={@ai_form}
          pending={@ai_pending}
          asks={@ai_asks}
          label={if written?(@text), do: "Ask AI", else: "What it's for (optional)"}
          button={if written?(@text), do: "Ask", else: "Write form"}
          closed={ai_closed_text(@ai)}
          sees={sees(@owner)}
          start_over={@draft_at && start_over_question(@form)}
        >
          {if written?(@text),
            do: "A change, or a question about the form.",
            else: "AI writes the form from the agency's PDF."}
        </.ai_writing>
      </:column>

      <section :if={text_shown?(assigns)} id="form-text" class="mb-8">
        <.form
          for={%{}}
          id="form-text-form"
          phx-change="edit_text"
          phx-submit="edit_text"
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

      <section id="form-try" class="mb-8">
        <.form_sample
          owner={@owner}
          written={written?(@text)}
          activities={@activities}
          activity={@activity}
          pages={@pages}
          previewing={@previewing}
          preview_error={@preview_error}
        >
          <:blank>The agency's blank form. AI writes the form from it.</:blank>
        </.form_sample>
      </section>
      <:bar>
        <.save_bar id="form-bar">
          <.button id="form-save" variant={:success} phx-click="save" phx-disable-with="Saving…">
            Save form
          </.button>
          <.button id="form-cancel" navigate={FormOwner.form_path(@owner, @form)} data-leave-ok>
            Cancel
          </.button>
          <.unsaved
            id="form-unsaved"
            unsaved={@text != @form.text or page_changed?(assigns)}
            kept={@draft_at != nil}
            saving={@ai_pending != nil}
            rev={@rev}
          />
        </.save_bar>
      </:bar>
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

  # Start over's question: what goes, and the version the form goes back to.
  defp start_over_question(form) do
    back =
      if Form.written?(form),
        do: "#{form.name} goes back to version #{form.version}, as saved.",
        else: "#{form.name} goes back to the agency's blank form."

    "Start over? Your changes and the conversation go. #{back}"
  end

  defp sees(%Organization{short_name: name}),
    do:
      "AI sees the agency's form and the field names every team in #{name} has, never a " <>
        "team's members or records."

  defp sees(_team),
    do: "AI sees the agency's form and your team's field names, never its members or records."
end
