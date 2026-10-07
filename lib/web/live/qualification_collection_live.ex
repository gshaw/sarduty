defmodule Web.QualificationCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Qualifications")}
  end

  # `?view=expiring` lists each current member's qualifications that run out in the next
  # 60 days, the dashboard's "qualifications expire" link (#205).
  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team

    case params["view"] do
      nil ->
        qualifications = list_qualifications_with_counts(current_team)
        {:noreply, assign(socket, view: :all, qualifications: qualifications)}

      "expiring" ->
        now = DateTime.utc_now()
        until = DateTime.add(now, BuildGroupRulePreview.expiring_days(), :day)
        expiring = MemberQualificationAward.expiring(current_team.id, now, until)
        {:noreply, assign(socket, view: :expiring, expiring: expiring)}

      _other ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team} />
    <h1 class="title mb-p">{@page_title}</h1>

    <div class="table-summary">
      <span class="table-summary-links">
        <.a navigate={~p"/teams/#{@current_team}/qualifications"}>All</.a>
        ·
        <.a navigate={~p"/teams/#{@current_team}/qualifications?view=expiring"}>
          Expiring in {BuildGroupRulePreview.expiring_days()} days
        </.a>
      </span>
      <span :if={@view == :all} class="table-summary-count">
        {Service.Format.count(length(@qualifications),
          one: "%d qualification",
          many: "%d qualifications"
        )}
      </span>
      <span :if={@view == :expiring} class="table-summary-count">
        {Service.Format.count(length(@expiring),
          one: "%d qualification expiring",
          many: "%d qualifications expiring"
        )}
      </span>
    </div>

    <.expiring_table :if={@view == :expiring} team={@current_team} expiring={@expiring} />

    <.table
      :if={@view == :all}
      id="qualification_collection"
      rows={@qualifications}
      class="w-full table-striped"
    >
      <:col :let={q} label="Qualification">
        <.a navigate={~p"/teams/#{@current_team}/qualifications/#{q.id}"}>{q.title}</.a>
      </:col>
      <:col :let={q} label="Active" class="w-px whitespace-nowrap" align="right">
        {q.active_count}
      </:col>
      <:col :let={q} label="Expired" class="w-px whitespace-nowrap" align="right">
        {q.expired_count}
      </:col>
      <:col :let={q} label="Total awards" class="w-px whitespace-nowrap" align="right">
        {q.total_count}
      </:col>
    </.table>

    <p :if={@view == :all and @qualifications == []} class="text-secondary-1">
      No qualifications yet. SAR Duty copies them from D4H when it refreshes.
    </p>
    """
  end

  attr :team, :map, required: true
  attr :expiring, :list, required: true

  defp expiring_table(assigns) do
    ~H"""
    <.table
      id="expiring_qualifications"
      rows={@expiring}
      row_id={&"expiring-#{&1.member_id}-#{&1.qualification_id}"}
      class="w-full table-striped"
    >
      <:col :let={row} label="Member">
        <.a navigate={~p"/teams/#{@team}/members/#{row.member_id}/qualifications"}>
          {row.member_name}
        </.a>
      </:col>
      <:col :let={row} label="Qualification">
        <.a navigate={~p"/teams/#{@team}/qualifications/#{row.qualification_id}"}>
          {row.qualification}
        </.a>
      </:col>
      <:col :let={row} label="Expires" align="right" class="w-1/12 whitespace-nowrap tabular-nums">
        {Service.Format.date_short(row.ends_at, @team.timezone)}
      </:col>
    </.table>
    <p :if={@expiring == []} class="text-secondary-1">
      No qualifications expire in the next {BuildGroupRulePreview.expiring_days()} days.
    </p>
    """
  end

  defp list_qualifications_with_counts(team) do
    now = DateTime.utc_now()

    awards_by_qualification =
      MemberQualificationAward
      |> join(:inner, [a], q in assoc(a, :qualification))
      |> where([a, q], q.team_id == ^team.id)
      |> select([a], %{
        qualification_id: a.qualification_id,
        starts_at: a.starts_at,
        ends_at: a.ends_at
      })
      |> Repo.all()
      |> Enum.group_by(& &1.qualification_id)

    team.id
    |> Qualification.get_all()
    |> Enum.map(fn q ->
      awards = Map.get(awards_by_qualification, q.id, [])

      %{
        id: q.id,
        title: q.title,
        total_count: length(awards),
        active_count: Enum.count(awards, &MemberQualificationAward.active?(&1, now)),
        expired_count: Enum.count(awards, &MemberQualificationAward.expired?(&1, now))
      }
    end)
  end
end
