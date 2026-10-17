defmodule Web.QualificationLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  import Web.Components.FilterBar
  import Web.Components.ViewSwitch

  alias App.Adapter.D4H
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo
  alias Service.StringHelpers

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    qualification = find_qualification(params["id"], current_team.id)

    {active_awards, expired_awards} =
      qualification |> list_awards_for_qualification() |> split_awards(DateTime.utc_now())

    view = view(params["view"])
    q = String.trim(params["q"] || "")
    awards = if view == :active, do: active_awards, else: expired_awards

    {:noreply,
     assign(socket,
       page_title: qualification.title,
       qualification: qualification,
       active_awards: active_awards,
       expired_awards: expired_awards,
       view: view,
       q: q,
       form: to_form(%{"q" => q}, as: "form"),
       awards: Enum.filter(awards, &StringHelpers.matches?(&1.member.name, q))
     )}
  end

  def handle_event("change", %{"form" => %{"q" => q}}, socket) do
    %{current_team: team, qualification: qualification, view: view} = socket.assigns
    {:noreply, push_patch(socket, to: path(team, qualification, view, q), replace: true)}
  end

  # Split awards into active and expired, keeping the most recent per member. Awards come
  # ordered by member name, then newest first. A member in the active list is left out of
  # the expired one.
  defp split_awards(awards, now) do
    {active_awards, expired_awards} =
      Enum.split_with(awards, &MemberQualificationAward.active?(&1, now))

    active_awards = dedup_by_member(active_awards)
    active_member_ids = MapSet.new(active_awards, & &1.member.id)

    expired_awards =
      expired_awards
      |> Enum.reject(fn award -> MapSet.member?(active_member_ids, award.member.id) end)
      |> dedup_by_member()

    {active_awards, expired_awards}
  end

  defp view(nil), do: :active
  defp view("expired"), do: :expired
  defp view(_other), do: raise(Web.Status.NotFound)

  defp path(team, qualification, view, q) do
    params =
      Enum.reject([view: view == :expired && "expired", q: q], &(elem(&1, 1) in [false, ""]))

    ~p"/teams/#{team}/qualifications/#{qualification.id}?#{params}"
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Qualifications" path={~p"/teams/#{@current_team}/qualifications"} />
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
          active_count={length(@active_awards)}
          expired_count={length(@expired_awards)}
          awards={@awards}
          view={@view}
          q={@q}
          form={@form}
          qualification={@qualification}
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
        <ul id="qualification-actions" class="action-list">
          <li :if={D4H.records?(@team)}>
            <.a
              id="qualification-edit"
              navigate={~p"/teams/#{@team}/qualifications/#{@qualification.id}/edit"}
            >
              Rename or delete
            </.a>
          </li>
          <li :if={!D4H.records?(@team)}>
            <.a external={true} href={D4H.build_url(@team, "/team/qualifications")}>
              Open D4H qualifications
            </.a>
          </li>
        </ul>
      </dd>
      <dt>Active members</dt>
      <dd>{length(@active_awards)}</dd>
      <dt>Expired awards</dt>
      <dd>{length(@expired_awards)}</dd>
      <dt>Total awards</dt>
      <dd>{length(@active_awards) + length(@expired_awards)}</dd>
    </dl>
    """
  end

  defp main_content(assigns) do
    ~H"""
    <.filter_bar
      for={@form}
      id="award_filter_form"
      count={Service.Format.count(length(@awards), one: "%d member", many: "%d members")}
      clear={path(@team, @qualification, @view, "")}
    >
      <:lead>
        <.view_switch label="Awards">
          <:view
            id="awards-active-link"
            patch={path(@team, @qualification, :active, @q)}
            current={@view == :active}
            count={@active_count}
          >
            Active
          </:view>
          <:view
            id="awards-expired-link"
            patch={path(@team, @qualification, :expired, @q)}
            current={@view == :expired}
            count={@expired_count}
          >
            Expired
          </:view>
        </.view_switch>
      </:lead>
      <:search field={@form[:q]} />
    </.filter_bar>

    <.table
      :if={@awards != []}
      id={"#{@view}_awards"}
      rows={@awards}
      class="table-striped"
    >
      <:col :let={award} label="Member">
        <.a navigate={~p"/teams/#{@team}/members/#{award.member.id}/qualifications"}>
          {award.member.name}
        </.a>
      </:col>
      <:col :let={award} label="Start" class="w-px whitespace-nowrap">
        {Service.Format.date_short(award.starts_at, @team.timezone)}
      </:col>
      <:col :let={award} label="End" class="w-px whitespace-nowrap">
        {Service.Format.date_short(award.ends_at, @team.timezone)}
      </:col>
    </.table>
    <.empty_state :if={@awards == [] and @q != ""} id="no-matching-awards" title="No members match">
      Change the search.
    </.empty_state>
    <p :if={@awards == [] and @q == ""} class="text-text-muted">No {@view} awards.</p>
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
