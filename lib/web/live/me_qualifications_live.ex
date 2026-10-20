defmodule Web.MeQualificationsLive do
  use Web, :live_view_app_layout

  import Web.Components.QualificationList

  alias App.Adapter.D4H
  alias App.ViewData.MemberRecords

  # A member's qualifications by when they expire (#308), /teams/:subdomain/me/qualifications.
  def mount(_params, _session, socket) do
    member = socket.assigns.member

    socket =
      socket
      |> assign(:page_title, "Qualifications")
      |> assign(:qualifications, MemberRecords.qualifications(member, DateTime.utc_now()))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Qualifications</h1>
      <.empty_state :if={@qualifications == []} id="no-qualifications" title="No qualifications">
        Qualifications you hold in {D4H.service_name(@member.team)} show here.
      </.empty_state>
      <.qualification_list
        :if={@qualifications != []}
        id="qualifications"
        groups={@qualifications}
        timezone={@member.team.timezone}
      />
    </div>
    """
  end
end
