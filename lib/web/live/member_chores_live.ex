defmodule Web.MemberChoresLive do
  use Web, {:live_view_app_layout, access: :team}

  on_mount {Web.Components.MemberPage, :own_page}

  import Web.ChoreText, only: [status_badge: 1]
  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Model.Chore
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Repo
  alias App.ViewData.MemberChores
  alias Web.ChoreText

  # A member sees only accepted chores (#1102): those are what count toward hours.
  def mount(_params, _session, socket) do
    if !Team.chores?(socket.assigns.current_team), do: raise(Web.Status.NotFound)
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    %{current_team: team, team_admin?: team_admin?} = socket.assigns
    member = team |> Member.find!(params["id"]) |> Repo.preload(:team)
    chores = Chore.get_all_for_member(member)
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    socket
    |> assign(page_title: "#{member.name} · Chores", member: member, today: today)
    |> assign(chores: if(team_admin?, do: chores, else: accepted(chores)))
    |> assign(stats: MemberChores.stats(chores, today.year))
    |> assign(log?: log?(socket.assigns, member))
    |> load_sidebar()
    |> then(&{:noreply, &1})
  end

  defp accepted(chores), do: Enum.filter(chores, &(&1.status == :accepted))

  defp log?(%{team_admin?: true, current_member: %Member{}, current_team: team}, member) do
    Member.current?(member, DateTime.utc_now()) and
      Member.counted?(member, Standing.retiring_ids(team))
  end

  defp log?(_assigns, _member), do: false

  def render(assigns) do
    ~H"""
    <.member_page
      current_member={@current_member}
      member={@member}
      tab={:chores}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      equipment={@equipment}
      fields?={@fields?}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <.heading_row>
        <p id="member-chores-summary">{ChoreText.tab_summary(@stats, @today.year, @team_admin?)}</p>
        <:action :if={@log?}>
          <.button
            id="member-chore-log"
            variant={:success}
            navigate={~p"/teams/#{@current_team}/chores/new?#{[member: @member.id]}"}
          >
            Log a chore
          </.button>
        </:action>
      </.heading_row>

      <.empty_state :if={@chores == []} id="no-member-chores" title="No chores yet">
        {if @team_admin?,
          do: "Chores logged for #{Member.first_name(@member)} show here.",
          else: "Chores a team admin accepts show here."}
      </.empty_state>

      <.table
        :if={@chores != []}
        id="member-chores"
        rows={@chores}
        row_id={&"chore-#{&1.id}"}
        class="table-striped table-stack"
      >
        <:col :let={chore} label="Date" class="w-px whitespace-nowrap">
          <.date_cell value={chore.date} timezone={@current_team.timezone} />
        </:col>
        <:col :let={chore} label="What they did" class="stack-title">
          <.a :if={@team_admin?} navigate={~p"/teams/#{@current_team}/chores/#{chore.id}"}>{chore.description}</.a>
          <span :if={!@team_admin?}>{chore.description}</span>
          <span class="hint block">{ChoreText.category_line(chore)}</span>
        </:col>
        <:col :let={chore} label="Hours" class="w-px whitespace-nowrap" align="right">
          <.hours_cell minutes={chore.minutes} />
        </:col>
        <:col :let={chore} label="" class="stack-optional w-px whitespace-nowrap">
          <.status_badge chore={chore} id={"chore-#{chore.id}-status"} />
        </:col>
      </.table>
    </.member_page>
    """
  end
end
