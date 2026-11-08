defmodule Web.Org.FormCollectionLive do
  use Web, :live_view_app_layout

  alias App.Model.Form

  # An organization's forms (#950), such as EMCR's Task report. SAR Duty admins upload
  # them; its organization admins try each and turn it on for every team.
  def mount(_params, _session, socket) do
    forms = Form.get_all(socket.assigns.current_organization)
    {:ok, assign(socket, page_title: "Forms", forms: forms)}
  end

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Forms</h1>
      <:action :if={@current_user.is_admin}>
        <.button
          id="upload-form"
          navigate={~p"/orgs/#{@current_organization}/forms/new"}
          variant={:success}
        >
          Upload form
        </.button>
      </:action>
    </.heading_row>

    <p class="lead measure">
      {@current_organization.short_name}'s forms for its teams, such as the claim after an
      incident. Once a form is on, team admins fill it in from an activity and download the
      PDF.
    </p>

    <.empty_state :if={@forms == []} id="no-forms" title="No forms yet">
      A SAR Duty site admin uploads {@current_organization.short_name}'s forms. Reach them at <.a href="mailto:support@sarduty.com">support@sarduty.com</.a>.
    </.empty_state>

    <.table :if={@forms != []} id="forms" rows={@forms} row_id={&"form-#{&1.id}"}>
      <:col :let={form} label="Form">
        <.a
          id={"form-#{form.id}-name"}
          navigate={~p"/orgs/#{@current_organization}/forms/#{form}"}
        >{form.name}</.a>
        <div :if={form.about} class="hint">{form.about}</div>
      </:col>
      <:col :let={form} label="For teams">
        <span :if={form.enabled} id={"form-#{form.id}-state"} class="text-success-text">On</span>
        <span :if={!form.enabled} id={"form-#{form.id}-state"} class="text-text-muted">Off</span>
      </:col>
      <:col :let={form} label="Version" class="max-md:hidden">
        <span id={"form-#{form.id}-version"}>{form.version}</span>
      </:col>
    </.table>
    """
  end
end
