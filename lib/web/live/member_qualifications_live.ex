defmodule Web.MemberQualificationsLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = find_member(params["id"])

    socket =
      socket
      |> assign(:page_title, "#{member.name} - Qualifications")
      |> assign(:member, member)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/#{@current_team.subdomain}/members/"} />
      <:item label="Qualifications" />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content member={@member} />
      </aside>
      <main class="content-2/3">
        <.member_tabs member={@member} active_tab={:qualifications} />
        <.qualifications_content member={@member} />
      </main>
    </div>
    """
  end

  defp qualifications_content(assigns) do
    ~H"""
    <.table
      :if={@member.member_qualification_awards != []}
      id="member_qualifications"
      rows={@member.member_qualification_awards}
      class="w-full table-striped"
    >
      <:col :let={award} label="Qualification">
        <.a navigate={~p"/#{@member.team.subdomain}/qualifications/#{award.qualification.id}"}>
          {award.qualification.title}
        </.a>
      </:col>
      <:col :let={award} label="Start" class="w-px whitespace-nowrap">
        {Service.Format.date_short(award.starts_at, @member.team.timezone)}
      </:col>
      <:col :let={award} label="End" class="w-px whitespace-nowrap">
        {Service.Format.date_short(award.ends_at, @member.team.timezone)}
      </:col>
      <:col :let={award} label="Status" class="w-px whitespace-nowrap">
        {award_status(award)}
      </:col>
    </.table>
    <p :if={@member.member_qualification_awards == []}>No qualifications found.</p>
    """
  end

  defp find_member(member_id) do
    qualification_awards_query =
      from(mqa in MemberQualificationAward,
        join: q in assoc(mqa, :qualification),
        order_by: [
          asc: q.title,
          asc: fragment("? IS NOT NULL", mqa.ends_at),
          desc: mqa.ends_at,
          desc: mqa.starts_at
        ],
        preload: [qualification: q]
      )

    Member
    |> Repo.get(member_id)
    |> Repo.preload([
      :team,
      member_qualification_awards: qualification_awards_query
    ])
  end

  defp award_status(award) do
    now = DateTime.utc_now()
    started = is_nil(award.starts_at) or DateTime.compare(award.starts_at, now) != :gt
    not_ended = is_nil(award.ends_at) or DateTime.compare(award.ends_at, now) == :gt

    if started and not_ended, do: "Active", else: "Expired"
  end
end
