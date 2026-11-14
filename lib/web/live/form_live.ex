defmodule Web.FormLive do
  use Web, :live_view_app_layout

  alias App.Document
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Operation.SetFormState
  alias App.Operation.TryForm
  alias App.Report.Query
  alias Web.FormCollectionLive
  alias Web.FormOwner

  # One form (#950), an organization's or a team's own (#1083): what it reads and asks,
  # whether it's off, testing, or on (#970), and a try: on Coast Range SAR, a made-up
  # team, for an organization's, and on the team's own activities for a team's. Found
  # through its owner, so another's is a 404. SAR Duty admins also replace it.
  def mount(%{"id" => id}, _session, socket) do
    owner = FormOwner.get(socket.assigns)
    form = Form.get(owner, id) || raise(Web.Status.NotFound)
    activities = TryForm.activities(form, owner)

    socket =
      socket
      |> assign(page_title: form.name, owner: owner, activities: activities)
      |> assign(activity: TryForm.first(activities))
      |> assign_form(form)

    {:ok, socket}
  end

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
      <:item label="Forms" path={FormOwner.forms_path(@owner)} />
      <:item label={@form.name} />
    </.breadcrumbs>
    <h1 class="title">{@form.name}</h1>
    <p :if={@form.about} class="lead measure">{@form.about}</p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl id="form-facts">
          <dt>{FormCollectionLive.state_label(@owner)}</dt>
          <dd id="form-state">
            {Form.state_label(@form.state)}
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
        <%!-- Two switches for three states, as Features nests one under another: on shows
        it to teams, and testing under it keeps it to drafts. Turning it on starts testing. --%>
        <section id="form-on-off" class="mb-8 measure flex flex-col gap-6">
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

        <section id="form-try" class="mb-8 measure">
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

        <section :if={@current_user.is_admin} id="form-replace" class="mb-8 measure">
          <h2 class="heading">Replace</h2>
          <p>
            Upload a new text or page.
          </p>
          <.button id="form-replace-button" navigate={FormOwner.edit_path(@owner, @form)}>
            Replace form
          </.button>
        </section>

        <section id="form-text">
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
    end
  end

  defp state_message(%Organization{}, %Form{state: :on, name: name}),
    do: "#{name} turned on for every team."

  defp state_message(_team, %Form{state: :on, name: name}), do: "#{name} turned on."
  defp state_message(_owner, %Form{state: :testing, name: name}), do: "#{name} set to testing."
  defp state_message(_owner, %Form{state: :off, name: name}), do: "#{name} turned off."
end
