defmodule Web.Org.FormLive do
  use Web, :live_view_app_layout

  alias App.Document
  alias App.Model.Form
  alias App.Operation.SetFormEnabled
  alias App.Operation.TryForm
  alias App.Report.Query

  # One of an organization's forms (#950): what it reads and asks, whether it's on for
  # its teams, and a try on Coast Range SAR, a made-up team. Found through the
  # organization, so another's is a 404. SAR Duty admins also replace it.
  def mount(%{"id" => id}, _session, socket) do
    form = Form.get(socket.assigns.current_organization, id) || raise(Web.Status.NotFound)
    activities = TryForm.activities(form)

    socket =
      socket
      |> assign(page_title: form.name, activities: activities)
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
      <:item label="Forms" path={~p"/orgs/#{@current_organization}/forms"} />
      <:item label={@form.name} />
    </.breadcrumbs>
    <h1 class="title">{@form.name}</h1>
    <p :if={@form.about} class="lead measure">{@form.about}</p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl id="form-facts">
          <dt>For teams</dt>
          <dd id="form-state">
            <span :if={@form.enabled} class="text-success-text">On</span>
            <span :if={!@form.enabled} class="text-text-muted">Off</span>
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
                href={~p"/orgs/#{@current_organization}/forms/#{@form}/page"}
                target="_blank"
              >{Service.Format.count(@pages, one: "%d page", many: "%d pages")}</.a>
            </div>
          </dd>
          <dt>Version</dt>
          <dd id="form-version">
            {@form.version}
            <span class="hint">
              {Service.Format.date_long(@form.updated_at, @current_organization.timezone)}
            </span>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <section id="form-on-off" class="mb-8 measure">
          <h2 class="heading">For teams</h2>
          <p>
            Once on, team admins of every team in {@current_organization.short_name} fill it in
            from an activity it shows on. Members never see it. Turning it off keeps every PDF
            already made.
          </p>
          <.button
            :if={!@form.enabled}
            id="form-on"
            phx-disable-with="Turning on…"
            type="button"
            phx-click="enabled"
            phx-value-enabled="true"
          >
            Turn on form
          </.button>
          <.button
            :if={@form.enabled}
            id="form-off"
            phx-disable-with="Turning off…"
            type="button"
            variant={:danger}
            phx-click="enabled"
            phx-value-enabled="false"
            data-confirm={"Turn off #{@form.name}? Team admins can no longer fill it in."}
          >
            Turn off form
          </.button>
        </section>

        <section id="form-try" class="mb-8 measure">
          <h2 class="heading">Try it</h2>
          <p>
            Prints it from Coast Range SAR, a made-up team, with each question's default answer.
            The PDF says SAMPLE across it.
          </p>
          <p :if={@activities == []} id="form-try-none">
            Coast Range SAR has no activity this form shows on.
          </p>
          <form
            :if={@activities != []}
            id="form-try-form"
            action={~p"/orgs/#{@current_organization}/forms/#{@form}/try"}
            method="get"
            target="_blank"
          >
            <.input
              id="form-try-activity"
              name="activity"
              type="select"
              label="Activity"
              value={@activity && @activity.id}
              options={Enum.map(@activities, &{activity_label(&1), &1.id})}
            />
            <.button id="form-try-button">Try form</.button>
          </form>
        </section>

        <section :if={@current_user.is_admin} id="form-replace" class="mb-8 measure">
          <h2 class="heading">Replace</h2>
          <p>
            Upload a new text or page.
          </p>
          <.button
            id="form-replace-button"
            navigate={~p"/orgs/#{@current_organization}/forms/#{@form}/edit"}
          >
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

  defp shows_on(nil), do: "Activities"
  defp shows_on(%Document{where: nil}), do: "Every activity"
  defp shows_on(%Document{where: where}), do: "Activities where #{Query.text(where)}"

  # A form with a layout draws its own page each time it prints (#950).
  defp layout?(%Document{layout: %{}}), do: true
  defp layout?(_doc), do: false

  defp asks(nil), do: []
  defp asks(%Document{asks: asks}), do: asks

  defp activity_label(activity),
    do:
      "#{activity.title}, #{Service.Format.date_short(activity.started_at, App.CoastRange.timezone())}"

  def handle_event("enabled", %{"enabled" => enabled}, socket) do
    %{form: form, current_user: user} = socket.assigns

    case SetFormEnabled.call(form, enabled == "true", user) do
      {:ok, form} ->
        message =
          if form.enabled,
            do: "#{form.name} turned on for every team.",
            else: "#{form.name} turned off."

        {:noreply, socket |> assign_form(form) |> put_flash(:info, message)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer turn this form on or off.")}
    end
  end
end
