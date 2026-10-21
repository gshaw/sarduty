defmodule Web.MeMilestonesLive do
  use Web, :live_view_app_layout

  import Web.Components.MilestoneList

  alias App.Adapter.D4H
  alias App.Model.MemberAwayPeriod
  alias App.ViewData.MemberRecords
  alias App.ViewData.Milestones

  # Every milestone a member reached (#389), /teams/:subdomain/me/milestones, from the
  # overview's Milestones card. Worked out on load; nothing is stored.
  def mount(_params, _session, socket) do
    member = socket.assigns.member
    now = DateTime.utc_now()

    milestones =
      member
      |> MemberRecords.attended(now)
      |> Milestones.build(
        member.joined_at,
        MemberAwayPeriod.for_member(member),
        now,
        member.team.timezone
      )

    socket =
      socket
      |> assign(:page_title, "Milestones")
      |> assign(:milestones, milestones)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Milestones</h1>
      <p class="lead">
        From the activities you attended in {D4H.service_name(@member.team)} and the day you joined.
      </p>
      <.empty_state :if={@milestones == []} id="no-milestones" title="No milestones yet">
        Your first comes at 100 hours, your first incident, or a year on the team.
      </.empty_state>
      <.milestone_list :if={@milestones != []} id="milestones" milestones={@milestones} />
    </div>
    """
  end
end
