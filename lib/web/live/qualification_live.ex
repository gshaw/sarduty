defmodule Web.QualificationLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    qualification = find_qualification(params["id"], current_team.id)
    awards = list_awards_for_qualification(qualification)

    now = DateTime.utc_now()

    # Split awards into active/expired, deduplicate by member (keep most recent per member).
    # Awards are already ordered by member name asc, starts_at desc.
    {active_awards, expired_awards} =
      awards
      |> Enum.split_with(fn award ->
        started = is_nil(award.starts_at) or DateTime.compare(award.starts_at, now) != :gt
        not_ended = is_nil(award.ends_at) or DateTime.compare(award.ends_at, now) == :gt
        started and not_ended
      end)

    # Keep only the most recent award per member in each section
    active_awards = dedup_by_member(active_awards)
    active_member_ids = MapSet.new(active_awards, & &1.member.id)

    # Exclude members who already appear in the active list
    expired_awards =
      expired_awards
      |> Enum.reject(fn award -> MapSet.member?(active_member_ids, award.member.id) end)
      |> dedup_by_member()

    socket =
      socket
      |> assign(:page_title, qualification.title)
      |> assign(:qualification, qualification)
      |> assign(:active_awards, active_awards)
      |> assign(:expired_awards, expired_awards)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Qualifications" path={~p"/#{@current_team.subdomain}/qualifications"} />
      <:item label={@qualification.title} />
    </.breadcrumbs>

    <h1 class="title">{@qualification.title}</h1>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content
          qualification={@qualification}
          active_awards={@active_awards}
          expired_awards={@expired_awards}
          team={@current_team}
        />
      </aside>
      <main class="content-2/3">
        <.main_content
          active_awards={@active_awards}
          expired_awards={@expired_awards}
          team={@current_team}
        />
      </main>
    </div>
    """
  end

  defp sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>Actions</dt>
      <dd>
        <ul class="action-list">
          <li>
            <.a external={true} href={D4H.build_url(@team, "/team/qualifications")}>
              Open D4H Qualifications
            </.a>
          </li>
        </ul>
      </dd>
      <dt>Active Members</dt>
      <dd>{length(@active_awards)}</dd>
      <dt>Expired Awards</dt>
      <dd>{length(@expired_awards)}</dd>
      <dt>Total Awards</dt>
      <dd>{length(@active_awards) + length(@expired_awards)}</dd>
    </dl>
    """
  end

  defp main_content(assigns) do
    ~H"""
    <h2 class="subtitle mb-p05">Active ({length(@active_awards)})</h2>
    <.table
      :if={@active_awards != []}
      id="active_awards"
      rows={@active_awards}
      class="w-full table-striped mb-p2"
    >
      <:col :let={award} label="Member">
        <.a navigate={~p"/#{@team.subdomain}/members/#{award.member.id}"}>
          {award.member.name}
        </.a>
      </:col>
      <:col :let={award} label="Start" class="w-px whitespace-nowrap" align="right">
        {Service.Format.short_date(award.starts_at, @team.timezone)}
      </:col>
      <:col :let={award} label="End" class="w-px whitespace-nowrap" align="right">
        {Service.Format.short_date(award.ends_at, @team.timezone)}
      </:col>
    </.table>
    <p :if={@active_awards == []} class="text-secondary-1 mb-p2">No active awards.</p>

    <h2 class="subtitle mb-p05">Expired ({length(@expired_awards)})</h2>
    <.table
      :if={@expired_awards != []}
      id="expired_awards"
      rows={@expired_awards}
      class="w-full table-striped"
    >
      <:col :let={award} label="Member">
        <.a navigate={~p"/#{@team.subdomain}/members/#{award.member.id}"}>
          {award.member.name}
        </.a>
      </:col>
      <:col :let={award} label="Start" class="w-px whitespace-nowrap" align="right">
        {Service.Format.short_date(award.starts_at, @team.timezone)}
      </:col>
      <:col :let={award} label="End" class="w-px whitespace-nowrap" align="right">
        {Service.Format.short_date(award.ends_at, @team.timezone)}
      </:col>
    </.table>
    <p :if={@expired_awards == []} class="text-secondary-1">No expired awards.</p>
    """
  end

  defp find_qualification(id, team_id) do
    Qualification
    |> where([q], q.id == ^id and q.team_id == ^team_id)
    |> Repo.one!()
  end

  defp list_awards_for_qualification(qualification) do
    MemberQualificationAward
    |> where([mqa], mqa.qualification_id == ^qualification.id)
    |> join(:inner, [mqa], m in assoc(mqa, :member))
    |> order_by([mqa, m], asc: m.name, desc: mqa.starts_at)
    |> preload([mqa, m], member: m)
    |> Repo.all()
  end

  defp dedup_by_member(awards) do
    awards
    |> Enum.uniq_by(& &1.member.id)
  end
end
