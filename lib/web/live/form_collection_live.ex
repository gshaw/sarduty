defmodule Web.FormCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Form
  alias App.Model.Organization
  alias App.Operation.SaveForm
  alias Web.FormOwner

  # An organization's forms (#950), such as EMCR's Task report, or a team's own (#1083),
  # one page for both (Web.FormOwner). Its admins start one from the agency's PDF with
  # New form, AI writes it (#1089), and they turn it on once it's written: for every team
  # in the organization, or for their own team.
  def mount(_params, _session, socket) do
    owner = FormOwner.get(socket.assigns)
    {:ok, assign(socket, page_title: title(owner), owner: owner, forms: Form.get_all(owner))}
  end

  defp title(%Organization{}), do: "Forms"
  defp title(_team), do: "Team settings · Forms"

  def render(assigns) do
    ~H"""
    <.team_settings_tabs :if={!match?(%Organization{}, @owner)} team={@owner} current={:forms} />
    <.heading_row>
      <h1 :if={match?(%Organization{}, @owner)} class="title">Forms</h1>
      <:action :if={SaveForm.allowed?(@owner, @current_user)}>
        <.button id="new-form" navigate={FormOwner.new_path(@owner)} variant={:success}>
          New form
        </.button>
      </:action>
    </.heading_row>

    <p :if={match?(%Organization{}, @owner)} class="lead measure">
      {@owner.short_name}'s forms for its teams, such as the claim after an incident. While a
      form is testing, team admins fill it in from an activity and download draft PDFs. Once
      it's on, they publish it.
    </p>
    <p :if={!match?(%Organization{}, @owner)} class="lead measure">
      {@owner.name}'s own forms, filled in from an activity. Only your team sees them. Start
      one from the agency's PDF. While a form is testing, you download draft PDFs. Once it's
      on, you publish it.
    </p>

    <.empty_state :if={@forms == []} id="no-forms" title="No forms yet">
      Choose New form and give SAR Duty the agency's PDF.
    </.empty_state>

    <.table :if={@forms != []} id="forms" rows={@forms} row_id={&"form-#{&1.id}"}>
      <:col :let={form} label="Form">
        <.a id={"form-#{form.id}-name"} navigate={FormOwner.form_path(@owner, form)}>{form.name}</.a>
        <div :if={form.about} class="hint">{form.about}</div>
      </:col>
      <:col :let={form} label={state_label(@owner)} class="whitespace-nowrap">
        <span :if={Form.written?(form)} id={"form-#{form.id}-state"} class={state_class(form.state)}>
          {Form.state_label(form.state)}
        </span>
        <span :if={!Form.written?(form)} id={"form-#{form.id}-state"} class="text-text-muted">
          Not written yet
        </span>
      </:col>
      <:col :let={form} label="Version" class="max-md:hidden">
        <span id={"form-#{form.id}-version"}>{form.version}</span>
      </:col>
    </.table>
    """
  end

  # Where it's off, testing, or on: every team's activities, or the team's.
  def state_label(%Organization{}), do: "For teams"
  def state_label(_team), do: "On activities"

  defp state_class(:on), do: "text-success-text"
  defp state_class(:testing), do: nil
  defp state_class(:off), do: "text-text-muted"
end
