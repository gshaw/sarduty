defmodule Web.MeQualificationsLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.ViewData.MemberRecords
  alias Web.QualificationText

  # A member's qualifications, soonest expiry first (#308), /teams/:subdomain/me/qualifications.
  def mount(_params, _session, socket) do
    member = socket.assigns.member
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:page_title, "Qualifications")
      |> assign(:now, now)
      |> assign(:qualifications, MemberRecords.qualifications(member, now))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Qualifications</h1>
      <.empty_state :if={@qualifications == []} id="no-qualifications" title="No qualifications">
        Qualifications you hold in {D4H.service_name(@member.team)} show here.
      </.empty_state>
      <.table
        :if={@qualifications != []}
        id="qualifications"
        rows={@qualifications}
        row_id={&"qualifications-#{&1.award.qualification_id}"}
        row_class={&QualificationText.row_class/1}
      >
        <:col :let={row} label="Qualification">{row.award.qualification.title}</:col>
        <:col :let={row} label="Expires" class="w-px whitespace-nowrap">
          {QualificationText.expires(row.award, @now, @member.team.timezone)}
          <.badge :if={row.status == :expiring} kind={:warning}>
            {QualificationText.days_left(row)}
          </.badge>
        </:col>
        <:col :let={row} label="First held" class="w-px whitespace-nowrap">
          {QualificationText.first_held(row, @member.team.timezone)}
        </:col>
      </.table>
    </div>
    """
  end
end
