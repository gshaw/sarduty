defmodule Web.MeLive do
  use Web, :live_view_app_layout

  import Web.Components.ActivityList

  alias App.Adapter.D4H
  alias App.ViewData.MemberRecords

  # A member's overview (#389), /teams/:subdomain/me, the first of the member area's
  # pages (Web.Navigation). `member` comes from the login (Web.UserAuth,
  # :ensure_team_member), never from the URL. Mostly read on a phone.
  def mount(_params, _session, socket) do
    member = socket.assigns.member

    socket =
      socket
      |> assign(:page_title, member.team.name)
      |> assign(:signed_up, MemberRecords.signed_up(member, DateTime.utc_now()))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">{@member.team.name}</h1>
      <p class="lead">{@member.name}</p>

      <%= if @signed_up != [] do %>
        <h2 class="heading mt-8">Signed up for</h2>
        <.activity_list
          id="signed-up"
          rows={@signed_up}
          timezone={@member.team.timezone}
          href={if !D4H.records?(@member.team), do: &D4H.activity_url(@member.team, &1)}
          external={true}
        />
      <% end %>
    </div>
    """
  end
end
