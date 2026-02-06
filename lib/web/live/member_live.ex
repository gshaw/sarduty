defmodule Web.MemberLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = find_member(params["id"])

    socket =
      socket
      |> assign(:page_title, member.name)
      |> assign(:member, member)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/#{@current_team.subdomain}/members/"} />
      <:item label={"#{@member.ref_id}"} />
    </.breadcrumbs>

    <h1 class="title">{@member.name}</h1>
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content member={@member} />
      </aside>
      <main class="content-2/3">
        <.main_content member={@member} />
      </main>
    </div>
    """
  end

  defp sidebar_content(assigns) do
    ~H"""
    <dl>
      <p><.member_image member={@member} /></p>
      <dt>Actions</dt>
      <dd>
        <ul class="action-list">
          <li>
            <.a external={true} href={D4H.member_url(@member)}>Open D4H Member</.a>
          </li>
          <li>
            <.a href={member_activities_path(@member)}>Member Activities</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  defp main_content(assigns) do
    ~H"""
    <dl>
      <dt>Role</dt>
      <dd>{@member.position}</dd>
      <dt>Email</dt>
      <dd>{@member.email}</dd>
      <dt>Phone</dt>
      <dd>{@member.phone}</dd>
      <dt>Address</dt>
      <dd>{@member.address}</dd>
      <dt>Joined</dt>
      <dd>{Service.Format.long_date(@member.joined_at, @member.team.timezone)}</dd>
    </dl>

    <h2 class="title">Qualifications</h2>
    <table :if={@member.member_qualification_awards != []}>
      <thead>
        <tr>
          <th>Qualification</th>
          <th>Start Date</th>
          <th>End Date</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={award <- @member.member_qualification_awards}>
          <td>{award.qualification.title}</td>
          <td>{Service.Format.short_date(award.starts_at, @member.team.timezone)}</td>
          <td>{Service.Format.short_date(award.ends_at, @member.team.timezone)}</td>
          <td>{award_status(award)}</td>
        </tr>
      </tbody>
    </table>
    <p :if={@member.member_qualification_awards == []}>No qualifications found.</p>
    """
  end

  defp member_activities_path(member),
    do: ~p"/#{member.team.subdomain}/members/#{member.id}/activities"

  defp find_member(member_id) do
    Member
    |> Repo.get(member_id)
    |> Repo.preload([:team, member_qualification_awards: :qualification])
  end

  defp award_status(award) do
    now = DateTime.utc_now()
    started = is_nil(award.starts_at) or DateTime.compare(award.starts_at, now) != :gt
    not_ended = is_nil(award.ends_at) or DateTime.compare(award.ends_at, now) == :gt

    if started and not_ended, do: "Active", else: "Expired"
  end
end
