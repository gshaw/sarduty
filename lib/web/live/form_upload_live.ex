defmodule Web.FormUploadLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton, only: [copy_code_block: 1]
  import Web.Components.FileDrop
  import Web.FormLive, only: [agents_hint: 1]

  alias App.Document.Draft
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.SaveForm
  alias App.Operation.TryForm
  alias Web.FormOwner

  # Upload form and Replace form (#950), for SAR Duty admins: the form's text and its page
  # PDF, prepared on a Mac. Saving checks the text on every team in the organization and
  # on Coast Range SAR, or on the team alone for a team's own form (#1083,
  # App.Operation.SaveForm).
  #
  # A team's form is changed here by its admins (#1083): each text the team admin's AI
  # agent checks arrives as their draft (App.Document.Draft), and they try it on an
  # activity and save it. Only SAR Duty admins upload a text file.
  def mount(params, _session, socket) do
    %{current_user: user} = socket.assigns
    owner = FormOwner.get(socket.assigns)
    unless SaveForm.allowed?(owner, user), do: raise(Web.Status.NotFound)

    form =
      case socket.assigns.live_action do
        :new -> nil
        :edit -> Form.get(owner, params["id"]) || raise(Web.Status.NotFound)
      end

    socket =
      socket
      |> assign(
        page_title: page_title(owner, form),
        owner: owner,
        form: form,
        errors: %{},
        # Files from a save that failed, so fixing one doesn't mean choosing both again.
        kept: %{}
      )
      |> assign(draft: nil, activities: [], activity: nil)
      |> allow_upload(:text, accept: ~w(.txt), max_entries: 1, max_file_size: 200_000)
      |> allow_upload(:page, accept: ~w(.pdf), max_entries: 1, max_file_size: 10_000_000)

    {:ok, follow_draft(socket)}
  end

  defp page_title(%Team{}, form), do: "#{form.name} · Change"
  defp page_title(_owner, nil), do: "Upload form"
  defp page_title(_owner, form), do: "#{form.name} · Replace"

  # A team's form follows the team admin's draft: the agent's latest text, as it arrives.
  defp follow_draft(%{assigns: %{owner: %Team{} = team, form: %Form{} = form}} = socket) do
    user = socket.assigns.current_user
    if connected?(socket), do: Draft.subscribe(team, user.id, form)
    assign_draft(socket, Draft.get(team, user.id, form))
  end

  defp follow_draft(socket), do: socket

  defp assign_draft(socket, nil), do: assign(socket, draft: nil, activities: [], activity: nil)

  defp assign_draft(socket, %Draft{} = draft) do
    %{form: form, owner: owner} = socket.assigns
    activities = TryForm.activities(%{form | text: draft.text}, owner)
    assign(socket, draft: draft, activities: activities, activity: TryForm.first(activities))
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
      <:item :if={@form} label={@form.name} path={FormOwner.form_path(@owner, @form)} />
      <:item label={crumb(@owner, @form)} />
    </.breadcrumbs>
    <h1 class="title">{title(@owner, @form)}</h1>

    <section :if={team?(@owner)} id="form-draft" class="mb-8 measure">
      <%= if @draft do %>
        <h2 class="heading">Your agent's draft</h2>
        <p id="form-draft-from">
          From {@draft.agent}, {Service.Format.minutes_ago(
            @draft.at,
            DateTime.utc_now(),
            @owner.timezone
          )}. <span :if={@draft.change}>{@draft.change}</span>
        </p>
        <p>
          Try it on an activity. Saving makes it version {SaveForm.next_version(@form)}, and {saved_state(
            @form
          )}
        </p>
        <p :if={@activities == []} id="form-draft-try-none">
          Your team has no activity this draft shows on.
        </p>
        <form
          :if={@activities != []}
          id="form-draft-try"
          action={FormOwner.try_path(@owner, @form)}
          method="get"
          target="_blank"
        >
          <input type="hidden" name="draft" value="1" />
          <.input
            id="form-draft-activity"
            name="activity"
            type="select"
            label="Activity"
            value={@activity && @activity.id}
            options={Enum.map(@activities, &{activity_label(&1, @owner), &1.id})}
          />
          <.button id="form-draft-try-button">Try draft</.button>
        </form>
        <.form_actions>
          <.button
            id="form-draft-save"
            variant={:success}
            phx-click="save-draft"
            phx-disable-with="Saving…"
          >
            Save draft
          </.button>
          <.button navigate={FormOwner.form_path(@owner, @form)}>Cancel</.button>
        </.form_actions>
        <details id="form-draft-text" class="mt-6">
          <summary>Its text</summary>
          <pre class="code-block"><code>{@draft.text}</code></pre>
        </details>
      <% else %>
        <h2 class="heading">Ask your AI agent</h2>
        <p id="form-draft-none">
          Tell it what to change. Each text it checks shows here, and you try it before you
          save it.
        </p>
        <.copy_code_block id="form-ask" value={FormOwner.agent_ask(@form)} label="Copy what to ask" />
        <.agents_hint team={@owner} />
      <% end %>
    </section>

    <section :if={upload?(@owner, @current_user)} id="form-upload-section">
      <h2 :if={team?(@owner)} class="heading">Upload instead</h2>
      <p class="lead measure">{checks_text(@owner)} Every expect must hold.</p>

      <.form
        for={%{}}
        as={:upload}
        id="form-upload"
        phx-change="validate"
        phx-submit="save"
        class="measure"
      >
        <.file_drop
          id="form-text-file"
          upload={@uploads.text}
          label={if @form, do: "Text (optional)", else: "Text"}
          kinds="a text file"
          errors={List.wrap(@errors[:text])}
        >
          The form's .txt file, starting with form and its name.
          <span :if={@form}>Leave it empty to keep its text.</span>
          <:current :if={@kept[:text]}>
            <span id="form-text-kept" class="hint">The text from your last try. Choose another to change it.</span>
          </:current>
        </.file_drop>

        <.file_drop
          id="form-page-file"
          upload={@uploads.page}
          label={if @form, do: "Page (optional)", else: "Page"}
          kinds="a PDF"
          errors={List.wrap(@errors[:page])}
        >
          The agency's PDF the values print on, when the text says page.
          <span :if={@form}>Leave it empty to keep its page.</span>
          <:current :if={@kept[:page]}>
            <span id="form-page-kept" class="hint">The page from your last try. Choose another to change it.</span>
          </:current>
        </.file_drop>

        <.form_actions>
          <.button variant={:success} phx-disable-with="Checking…">
            {if @form, do: "Replace form", else: "Upload form"}
          </.button>
          <.button navigate={cancel_path(@owner, @form)}>Cancel</.button>
        </.form_actions>
      </.form>
    </section>
    """
  end

  defp team?(owner), do: match?(%Team{}, owner)

  # A team's form takes a text file from SAR Duty admins only; its admins use their agent.
  defp upload?(%Team{}, user), do: user.is_admin
  defp upload?(_owner, _user), do: true

  defp crumb(%Team{}, _form), do: "Change"
  defp crumb(_owner, nil), do: "Upload form"
  defp crumb(_owner, _form), do: "Replace"

  defp title(%Team{}, form), do: "Change #{form.name}"
  defp title(_owner, nil), do: "Upload form"
  defp title(_owner, form), do: "Replace #{form.name}"

  defp saved_state(%Form{state: :off}), do: "it stays off."
  defp saved_state(%Form{state: :testing}), do: "it's what testing prints."
  defp saved_state(%Form{state: :on}), do: "team admins publish it right away."

  defp activity_label(activity, team),
    do: "#{activity.title}, #{Service.Format.date_short(activity.started_at, team.timezone)}"

  def handle_info({:form_draft, draft}, socket), do: {:noreply, assign_draft(socket, draft)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    name = if ref == socket.assigns.uploads.text.ref, do: :text, else: :page
    {:noreply, cancel_upload(socket, name, ref)}
  end

  def handle_event("save-draft", _params, %{assigns: %{draft: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "The draft is gone. Ask your agent to check it again.")}
  end

  def handle_event("save-draft", _params, socket) do
    %{owner: owner, form: form, draft: draft, current_user: user} = socket.assigns

    case SaveForm.call(owner, form, draft.text, nil, user) do
      {:ok, saved} ->
        Draft.delete(owner, user.id, form)

        socket =
          socket
          |> put_flash(:info, draft_saved_message(form, saved))
          |> push_navigate(to: FormOwner.form_path(owner, saved))

        {:noreply, socket}

      {:error, _field, message} ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer change this team's forms.")}
    end
  end

  def handle_event("save", _params, socket) do
    %{form: form, kept: kept} = socket.assigns
    kept = %{text: upload(socket, :text, kept), page: upload(socket, :page, kept)}
    socket = assign(socket, kept: kept)

    case kept.text || (form && Form.written?(form) && form.text) do
      text when is_binary(text) -> save(socket, text, kept.page)
      _none -> {:noreply, assign(socket, errors: %{text: "Upload the form's text, a .txt file."})}
    end
  end

  defp save(socket, text, page) do
    %{owner: owner, current_user: user, form: form} = socket.assigns

    case SaveForm.call(owner, form, text, page, user) do
      {:ok, saved} ->
        socket =
          socket
          |> put_flash(:info, saved_message(form, saved))
          |> push_navigate(to: FormOwner.form_path(owner, saved))

        {:noreply, socket}

      {:error, field, message} ->
        {:noreply, assign(socket, errors: %{field => message})}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Only a SAR Duty site admin uploads a form.")}
    end
  end

  defp cancel_path(owner, nil), do: FormOwner.forms_path(owner)
  defp cancel_path(owner, form), do: FormOwner.form_path(owner, form)

  defp checks_text(%Organization{short_name: name}),
    do: "Saving checks the text on every team in #{name} and on Coast Range SAR."

  defp checks_text(team), do: "Saving checks the text on #{team.name}."

  defp saved_message(nil, saved), do: "#{saved.name} uploaded."

  defp saved_message(%Form{version: same}, %Form{version: same} = saved),
    do: "#{saved.name} saved."

  defp saved_message(_form, saved), do: "#{saved.name} replaced. It's version #{saved.version}."

  defp draft_saved_message(%Form{version: same}, %Form{version: same} = saved),
    do: "#{saved.name} saved."

  defp draft_saved_message(_form, saved),
    do: "#{saved.name} saved. It's version #{saved.version}."

  # A file just chosen, or the one kept from the last try.
  defp upload(socket, name, kept) do
    case consume_uploaded_entries(socket, name, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> bytes
      [] -> kept[name]
    end
  end
end
