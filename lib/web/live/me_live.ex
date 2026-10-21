defmodule Web.MeLive do
  use Web, :live_view_app_layout

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
        <.table id="signed-up" rows={@signed_up} row_id={&"signed-up-#{&1.id}"}>
          <:col :let={attendance} label="Date" class="w-px whitespace-nowrap">
            {Service.Format.date_short(attendance.started_at, @member.team.timezone)}
          </:col>
          <:col :let={attendance} label="Activity">
            <.d4h_activity_link team={@member.team} activity={attendance.activity} />
          </:col>
          <:col :let={attendance} label="Kind" class="w-px whitespace-nowrap max-md:hidden">
            <.activity_kind_mark activity={attendance.activity} />
          </:col>
        </.table>
      <% end %>
    </div>
    """
  end
end
