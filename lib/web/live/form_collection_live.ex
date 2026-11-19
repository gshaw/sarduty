defmodule Web.FormCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.OrgLogo
  import Web.Components.RowLink
  import Web.Components.TeamSettingsTabs

  alias App.Model.Form
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.SaveForm
  alias App.Repo
  alias Web.FormOwner

  # An organization's forms (#950), such as EMCR's Task report, or a team's (#1083), one
  # page for both (Web.FormOwner). Its admins start one from the agency's PDF with New
  # form, AI writes it (#1089), and they turn it on once it's written: for every team in
  # the organization, or for their own team. A team's tab shows on every team, as Fields
  # does: the team's own forms under its logo while team forms are on, then its
  # organization's, read-only, under its.
  def mount(_params, _session, socket) do
    owner = FormOwner.viewer(socket.assigns)
    {:ok, socket |> assign(page_title: title(owner), owner: owner) |> assign_forms(owner)}
  end

  defp assign_forms(socket, %Organization{} = organization),
    do: assign(socket, forms: Form.get_all(organization))

  defp assign_forms(socket, team) do
    team = Repo.preload(team, :organization)
    organization_forms = Form.organization_forms(team)
    names = MapSet.new(organization_forms, & &1.name)

    assign(socket,
      own?: team.forms_enabled,
      forms: if(team.forms_enabled, do: Form.get_all(team), else: []),
      replaced: names,
      organization_forms: organization_forms,
      organization: team.organization,
      team_logo: Team.logo_file(team.subdomain) && Web.TeamController.logo_url(team, :square),
      organization_logo:
        team.organization && team.organization.logo_at &&
          Web.OrganizationController.logo_url(team.organization)
    )
  end

  defp title(%Organization{}), do: "Forms"
  defp title(_team), do: "Team settings · Forms"

  def render(%{owner: %Organization{}} = assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Forms</h1>
      <:action :if={SaveForm.allowed?(@owner, @current_user)}>
        <.button id="new-form" navigate={FormOwner.new_path(@owner)} variant={:success}>
          New form
        </.button>
      </:action>
    </.heading_row>

    <p class="lead measure">
      The forms {@owner.short_name}'s teams fill in from an activity. Each team sees them on
      its Forms tab, read-only.
    </p>

    <.empty_state :if={@forms == []} id="no-forms" title="No forms yet" class="mt-8">
      Choose New form and give SAR Duty the agency's PDF.
    </.empty_state>

    <%!-- A reader's width, so each row's chevron sits by its words, as on a team's tab. --%>
    <div class="mt-8 max-w-3xl">
      <.form_rows id="forms" forms={@forms} owner={@owner} />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@owner} current={:forms} />
    <div class="measure">
      <p class="lead">
        The forms your team fills in from an activity{from(@own?, @organization)}.
      </p>
      <p :if={@own? and @organization} id="forms-who-changes">
        Write your team's own forms here. Only {@organization.short_name} can change its forms.
      </p>
      <p :if={!@own? and @organization} id="forms-who-changes">
        Only {@organization.short_name} can change its forms.
      </p>
    </div>

    <.empty_state
      :if={!@own? and @organization_forms == []}
      id="no-forms"
      title="No forms yet"
      class="mt-8"
    >
      {no_forms(@organization)}
    </.empty_state>

    <%!-- A reader's width, so each row's chevron sits by its words, as on Fields. --%>
    <div class="mt-8 max-w-3xl">
      <section :if={@own?} id="forms-team" class="mb-8">
        <.heading_row class="mb-4">
          <h2 class="heading flex items-center gap-3">
            <.org_logo id="forms-team-logo" src={@team_logo} name={@owner.name} />
            {@owner.name}'s forms
          </h2>
          <:action :if={SaveForm.allowed?(@owner, @current_user)}>
            <.button id="new-form" navigate={FormOwner.new_path(@owner)} variant={:success}>
              New form
            </.button>
          </:action>
        </.heading_row>
        <p :if={@forms == []} id="no-forms" class="hint">
          None yet. New form starts one from the agency's PDF.
        </p>
        <.form_rows
          id="forms"
          forms={@forms}
          owner={@owner}
          replaced={@replaced}
          organization={@organization}
        />
      </section>

      <section :if={@organization_forms != []} id="forms-organization" class="mb-8">
        <h2 class="heading flex items-center gap-3 mb-4">
          <.org_logo
            id="forms-organization-logo"
            src={@organization_logo}
            name={@organization.short_name}
          />
          {@organization.short_name}'s forms
        </h2>
        <.form_rows id="organization-forms" forms={@organization_forms} owner={@owner} />
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :forms, :list, required: true
  attr :owner, :any, required: true, doc: "the team or organization whose page it is"
  attr :replaced, :any, default: MapSet.new()
  attr :organization, Organization, default: nil

  # Rows like Fields': the name, its state in grey, a Replaced tag, and its description.
  defp form_rows(assigns) do
    ~H"""
    <ul :if={@forms != []} id={@id} class="row-links">
      <li :for={form <- @forms} id={"form-#{form.id}"}>
        <.row_link navigate={FormOwner.form_path(@owner, form)}>
          <strong id={"form-#{form.id}-name"} class="text-link">{form.name}</strong>
          <span id={"form-#{form.id}-state"} class="hint ml-1">{row_state(form)}</span>
          <.badge
            :if={MapSet.member?(@replaced, form.name)}
            id={"form-#{form.id}-replaced"}
            kind={:warning}
            class="ml-1"
          >
            Replaced by {@organization.short_name}'s
          </.badge>
          <span :if={MapSet.member?(@replaced, form.name)} class="hint block">
            {@organization.short_name}'s {form.name} shows on your activities instead.
          </span>
          <span :if={form.about && !MapSet.member?(@replaced, form.name)} class="hint line-clamp-2">
            {form.about}
          </span>
        </.row_link>
      </li>
    </ul>
    """
  end

  defp row_state(form),
    do: if(Form.written?(form), do: Form.state_label(form.state), else: "Not written yet")

  defp from(true, %Organization{short_name: name}), do: ", from your team and #{name}"
  defp from(_own?, %Organization{short_name: name}), do: ", from #{name}"
  defp from(_own?, nil), do: ""

  defp no_forms(%Organization{short_name: name}),
    do: "When #{name} adds a form, such as a task report, it shows here and on your activities."

  defp no_forms(nil), do: "Your team has no forms in SAR Duty."
end
