defmodule Web.FormLive do
  use Web, :live_view_app_layout

  import Web.Components.PageActions

  alias App.Document
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Operation.AskAI
  alias App.Operation.DeleteForm
  alias App.Operation.SaveForm
  alias App.Operation.SetFormState
  alias App.Operation.TryForm
  alias App.Report.Query
  alias Web.FormCollectionLive
  alias Web.FormOwner

  # One form (#950), an organization's or a team's own (#1083): what it reads and asks,
  # whether it's off, testing, or on (#970), and a try: on Coast Range SAR, a made-up
  # team, for an organization's, and on the team's own activities for a team's. Found
  # through its owner, so another's is a 404. A new form says it's not written yet, and
  # nothing more, until it has its text (#1088). With AI writing open, its admins write it
  # on Change form (#1089), the organization's or the team's, and give it the agency's
  # new PDF there; nobody uploads a form's text. Delete form shows
  # while no PDF was published from it; after, turning it off is the way.
  def mount(%{"id" => id}, _session, socket) do
    owner = FormOwner.get(socket.assigns)
    form = Form.get(owner, id) || raise(Web.Status.NotFound)
    activities = TryForm.activities(form, owner)

    socket =
      socket
      |> assign(page_title: form.name, owner: owner, activities: activities)
      |> assign(change?: change?(owner, socket.assigns.current_user))
      |> assign(delete?: DeleteForm.allowed?(form, socket.assigns.current_user))
      |> assign(activity: TryForm.first(activities))
      |> assign_form(form)

    {:ok, socket}
  end

  # Change form writes the form with AI writing (#1089), for whoever saves the owner's
  # forms while AI writing is open to them.
  defp change?(owner, user),
    do:
      SaveForm.allowed?(owner, user) and
        AskAI.check(owner, user, DateTime.utc_now(), :form) != {:error, :off}

  defp assign_form(socket, form) do
    page = Form.page_bytes(form)
    assign(socket, form: form, doc: parse(form.text), pages: page && pages(page))
  end

  defp parse(text) do
    case Document.parse(text) do
      {:ok, doc} -> doc
      {:error, _error} -> nil
    end
  end

  defp pages(page) do
    case Service.PDFPages.count(page) do
      {:ok, pages} -> pages
      :error -> nil
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
      <:item label={@form.name} />
    </.breadcrumbs>
    <h1 class="title">{@form.name}</h1>
    <.page_actions :if={@change? or @delete?} id="form-actions">
      <:action :if={@change?}>
        <.a id="form-change" navigate={FormOwner.change_path(@owner, @form)}>Change form</.a>
      </:action>
      <:action :if={@delete?}>
        <.a
          id="form-delete"
          href="#"
          phx-click="delete"
          phx-disable-with="Deleting…"
          {Web.DeleteConfirm.form(@form)}
        >Delete form</.a>
      </:action>
    </.page_actions>
    <p :if={@form.about} class="lead measure">{@form.about}</p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl id="form-facts">
          <dt>{FormCollectionLive.state_label(@owner)}</dt>
          <dd id="form-state">
            {if Form.written?(@form), do: Form.state_label(@form.state), else: "Not written yet"}
          </dd>
          <dt>Shows on</dt>
          <dd id="form-shows-on">{shows_on(@doc)}</dd>
          <dt>Questions</dt>
          <dd id="form-questions">
            <div :if={asks(@doc) == []}>None</div>
            <div :for={ask <- asks(@doc)}>{ask.label}</div>
          </dd>
          <dt>Page</dt>
          <dd id="form-page">
            <div :if={is_nil(@pages) and layout?(@doc)}>Drawn by its layout</div>
            <div :if={is_nil(@pages) and not layout?(@doc)}>None</div>
            <div :if={@pages}>
              <.a
                href={FormOwner.page_path(@owner, @form)}
                target="_blank"
              >{Service.Format.count(@pages, one: "%d page", many: "%d pages")}</.a>
            </div>
          </dd>
          <dt>Version</dt>
          <dd id="form-version">
            {@form.version}
            <span class="hint">
              {Service.Format.date_long(@form.updated_at, @owner.timezone)}
            </span>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <p :if={!Form.written?(@form)} id="form-not-written" class="mb-8 measure">
          {@form.name} isn't written yet. It stays off until it is.
        </p>

        <%!-- Two switches for three states, as Features nests one under another: on shows
        it to teams, and testing under it keeps it to drafts. Turning it on starts testing. --%>
        <section
          :if={Form.written?(@form)}
          id="form-on-off"
          class="mb-8 measure flex flex-col gap-6"
        >
          <h2 class="heading mb-0">{FormCollectionLive.state_label(@owner)}</h2>
          <.switch
            id="form-on"
            label="Turned on"
            checked={@form.state != :off}
            phx-click="state"
            phx-value-state={if @form.state == :off, do: "testing", else: "off"}
            {off_confirm(@form)}
          >
            {on_hint(@owner)}
          </.switch>
          <div class="pl-8">
            <.switch
              id="form-testing"
              label="Testing"
              checked={@form.state != :on}
              disabled={@form.state == :off}
              phx-click="state"
              phx-value-state={if @form.state == :testing, do: "on", else: "testing"}
              {publish_confirm(@owner, @form)}
            >
              Draft PDFs only, marked DRAFT. Turn testing off and team admins publish it, with an
              ID and a verify code.
            </.switch>
          </div>
        </section>

        <section :if={Form.written?(@form)} id="form-try" class="mb-8 measure">
          <h2 class="heading">Try it</h2>
          <p>{try_text(@owner)} The PDF says SAMPLE across it.</p>
          <p :if={@activities == []} id="form-try-none">{try_none(@owner)}</p>
          <form
            :if={@activities != []}
            id="form-try-form"
            action={FormOwner.try_path(@owner, @form)}
            method="get"
            target="_blank"
          >
            <.input
              id="form-try-activity"
              name="activity"
              type="select"
              label="Activity"
              value={@activity && @activity.id}
              options={Enum.map(@activities, &{activity_label(&1, @owner), &1.id})}
            />
            <.button id="form-try-button">Try form</.button>
          </form>
        </section>

        <section :if={Form.written?(@form)} id="form-text">
          <h2 class="heading">Its text</h2>
          <p class="measure">
            What the form reads, what it asks, and where each value goes on the page.
          </p>
          <pre class="code-block"><code>{@form.text}</code></pre>
        </section>
      </main>
    </div>
    """
  end

  defp on_hint(%Organization{short_name: name}),
    do:
      "Team admins of every team in #{name} fill it in from an activity it shows on. " <>
        "Members never see it. Turning it off keeps every PDF already published."

  defp on_hint(team),
    do:
      "Team admins fill it in from an activity it shows on. Only #{team.name} sees it, " <>
        "and members never do. Turning it off keeps every PDF already published."

  defp try_text(%Organization{}),
    do: "Prints it from Coast Range SAR, a made-up team, with each question's default answer."

  defp try_text(_team),
    do: "Prints it from one of your activities, with each question's default answer."

  defp try_none(%Organization{}), do: "Coast Range SAR has no activity this form shows on."
  defp try_none(_team), do: "Your team has no activity this form shows on."

  defp off_confirm(%Form{state: :off}), do: %{}

  defp off_confirm(form),
    do: %{
      "data-confirm" => "Turn off #{form.name}? Team admins can no longer fill it in.",
      "data-confirm-button" => "Turn off"
    }

  defp publish_confirm(owner, %Form{state: :testing} = form),
    do: %{
      "data-confirm" => "Turn off testing for #{form.name}? #{who_publishes(owner)}",
      "data-confirm-button" => "Turn off testing"
    }

  defp publish_confirm(_owner, _form), do: %{}

  defp who_publishes(%Organization{}), do: "Team admins of every team can then publish it."
  defp who_publishes(_team), do: "Team admins can then publish it."

  defp shows_on(nil), do: "Activities"
  defp shows_on(%Document{where: nil}), do: "Every activity"
  defp shows_on(%Document{where: where}), do: "Activities where #{Query.text(where)}"

  # A form with a layout draws its own page each time it prints (#950).
  defp layout?(%Document{layout: %{}}), do: true
  defp layout?(_doc), do: false

  defp asks(nil), do: []
  defp asks(%Document{asks: asks}), do: asks

  # Coast Range SAR's activities in its own zone, a team's in the team's.
  defp activity_label(activity, owner),
    do: "#{activity.title}, #{Service.Format.date_short(activity.started_at, try_zone(owner))}"

  defp try_zone(%Organization{}), do: App.CoastRange.timezone()
  defp try_zone(team), do: team.timezone

  def handle_event("state", %{"state" => state}, socket) when state in ~w(off testing on) do
    %{form: form, owner: owner, current_user: user} = socket.assigns

    case SetFormState.call(form, String.to_existing_atom(state), user) do
      {:ok, form} ->
        {:noreply, socket |> assign_form(form) |> put_flash(:info, state_message(owner, form))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer turn this form on or off.")}

      {:error, :not_written} ->
        {:noreply, put_flash(socket, :error, "Save the form's text before you turn it on.")}
    end
  end

  def handle_event("delete", _params, socket) do
    %{form: form, owner: owner, current_user: user} = socket.assigns

    case DeleteForm.call(form, user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Deleted #{form.name}.")
         |> push_navigate(to: FormOwner.forms_path(owner))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer delete this form.")}

      {:error, :published} ->
        {:noreply,
         put_flash(socket, :error, "Turn #{form.name} off instead. PDFs were published from it.")}
    end
  end

  defp state_message(%Organization{}, %Form{state: :on, name: name}),
    do: "#{name} turned on for every team."

  defp state_message(_team, %Form{state: :on, name: name}), do: "#{name} turned on."
  defp state_message(_owner, %Form{state: :testing, name: name}), do: "#{name} set to testing."
  defp state_message(_owner, %Form{state: :off, name: name}), do: "#{name} turned off."
end
