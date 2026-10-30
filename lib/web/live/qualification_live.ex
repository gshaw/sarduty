defmodule Web.QualificationLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.Adapter.D4H
  alias App.Model.GroupMember
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.SaveTitledRecord
  alias App.Repo
  alias App.ViewModel.MemberFilterViewModel
  alias App.ViewModel.QualificationFilterViewModel
  alias Service.StringHelpers

  @views ["active", "expired", "all"]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :organization_name, Team.organization_name(socket.assigns.current_team))}
  end

  # `group` keeps the awards of a group's members (#367).
  def handle_params(params, _uri, socket) do
    case QualificationFilterViewModel.validate(params, @views) do
      {:ok, filter_options, changeset} ->
        {:noreply, assign_awards(socket, params["id"], filter_options, changeset)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  # Only a Records team deletes its own qualifications; D4H's are deleted in D4H.
  defp delete_confirm(team, qualification) do
    if D4H.records?(team) and !qualification.organization_owned,
      do: Web.DeleteConfirm.qualification(team, qualification),
      else: %{}
  end

  defp assign_awards(socket, id, filter_options, changeset) do
    current_team = socket.assigns.current_team
    qualification = find_qualification(id, current_team.id)

    {active_awards, expired_awards, standings} = load_awards(current_team, qualification)

    view = String.to_existing_atom(filter_options.view)
    q = filter_options.q || ""

    group_member_ids = GroupMember.member_ids(current_team.id, filter_options.group)

    assign(socket,
      page_title: qualification.title,
      qualification: qualification,
      delete_confirm: delete_confirm(current_team, qualification),
      active_awards: active_awards,
      expired_awards: expired_awards,
      expired_ids: MapSet.new(expired_awards, & &1.id),
      standings: standings,
      filter_options: filter_options,
      view: view,
      q: q,
      form: to_form(changeset, as: "form"),
      awards:
        view
        |> view_awards(active_awards, expired_awards)
        |> Enum.filter(&shown?(&1, q, group_member_ids))
    )
  end

  # Active and expired awards, and the standing of everyone holding one.
  defp load_awards(team, qualification) do
    now = DateTime.utc_now()
    awards = list_awards_for_qualification(qualification)
    {active, expired} = MemberQualificationAward.split_by_member(awards, now)
    {active, expired, Standing.by_member(team, Enum.map(awards, & &1.member), now)}
  end

  # All is each member's latest award, so a member is in it once, by name.
  defp view_awards(:active, active_awards, _expired_awards), do: active_awards
  defp view_awards(:expired, _active_awards, expired_awards), do: expired_awards

  defp view_awards(:all, active_awards, expired_awards),
    do: Enum.sort_by(active_awards ++ expired_awards, & &1.member.name)

  defp shown?(award, q, group_member_ids) do
    StringHelpers.matches?(award.member.name, q) and
      (is_nil(group_member_ids) or MapSet.member?(group_member_ids, award.member.id))
  end

  # The page offers Delete only to a Records team, and D4H's qualifications stay D4H's.
  def handle_event("delete", _params, %{assigns: %{delete_confirm: confirm}} = socket)
      when confirm == %{},
      do: {:noreply, socket}

  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, qualification: qualification} = socket.assigns

    case SaveTitledRecord.delete(team, :qualification, qualification, user, DateTime.utc_now()) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Deleted #{qualification.title}.")
          |> push_navigate(to: ~p"/teams/#{team}/qualifications")

        {:noreply, socket}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    %{current_team: team, qualification: qualification, filter_options: filter_options} =
      socket.assigns

    params = Map.put(form_params, "view", filter_options.view)

    case QualificationFilterViewModel.validate(params, @views) do
      {:ok, filter_options, _changeset} ->
        {:noreply,
         push_patch(socket, to: awards_path(team, qualification, filter_options), replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp awards_path(team, qualification, filter_options, changes \\ []) do
    params =
      filter_options
      |> struct(changes)
      |> QualificationFilterViewModel.query_params("active")

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
          team={@current_team}
          organization_name={@organization_name}
          delete_confirm={@delete_confirm}
        />
      </aside>
      <main class="content-2/3">
        <.main_content
          active_count={length(@active_awards)}
          expired_count={length(@expired_awards)}
          awards={@awards}
          standings={@standings}
          expired_ids={@expired_ids}
          view={@view}
          q={@q}
          form={@form}
          filter_options={@filter_options}
          qualification={@qualification}
          team={@current_team}
        />
      </main>
    </div>
    """
  end

  # Facts first, then Actions, as on every record's page.
  defp sidebar_content(assigns) do
    # A Records team can't rename its organization's qualification, and has no D4H to open.
    %{team: team, qualification: qualification} = assigns

    assigns =
      assign(assigns, :actions?, !D4H.records?(team) or !qualification.organization_owned)

    ~H"""
    <dl>
      <%= if @qualification.organization_owned do %>
        <dt>Belongs to</dt>
        <dd id="qualification-organization">
          {@organization_name || "Your organization"}
          <span class="hint block">
            Only {@organization_name || "your organization"} can rename or delete it.
          </span>
        </dd>
      <% end %>
      <dt :if={@actions?}>Actions</dt>
      <dd :if={@actions?}>
        <ul id="qualification-actions" class="action-list">
          <li :if={D4H.records?(@team) and !@qualification.organization_owned}>
            <.a
              id="qualification-edit"
              navigate={~p"/teams/#{@team}/qualifications/#{@qualification.id}/edit"}
            >Rename</.a>
          </li>
          <li :if={D4H.records?(@team) and !@qualification.organization_owned}>
            <.a
              id="qualification-delete"
              href="#"
              phx-click="delete"
              phx-disable-with="Deleting…"
              {@delete_confirm}
            >Delete</.a>
          </li>
          <li :if={!D4H.records?(@team)}>
            <.a
              id="qualification-d4h"
              external={true}
              href={D4H.qualification_url(@team, @qualification)}
            >Open in {D4H.service_name(@team)}</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  defp view_count(:active, active, _expired), do: active
  defp view_count(:expired, _active, expired), do: expired
  defp view_count(:all, active, expired), do: active + expired

  defp main_content(assigns) do
    ~H"""
    <.stat_switch label="Members">
      <:view
        id="awards-all-link"
        patch={awards_path(@team, @qualification, @filter_options, view: "all")}
        current={@view == :all}
        count={@active_count + @expired_count}
      >
        All
      </:view>
      <:view
        id="awards-active-link"
        patch={awards_path(@team, @qualification, @filter_options, view: "active")}
        current={@view == :active}
        count={@active_count}
      >
        Active
      </:view>
      <:view
        id="awards-expired-link"
        patch={awards_path(@team, @qualification, @filter_options, view: "expired")}
        current={@view == :expired}
        count={@expired_count}
      >
        Expired
      </:view>
    </.stat_switch>

    <.filter_bar
      for={@form}
      id="award_filter_form"
      count={Service.Format.count(length(@awards), one: "%d member", many: "%d members")}
      repeats={length(@awards) == view_count(@view, @active_count, @expired_count)}
      clear={awards_path(@team, @qualification, %QualificationFilterViewModel{view: "#{@view}"})}
      path_fn={&awards_path(@team, @qualification, @filter_options, &1)}
    >
      <:search field={@form[:q]} />
      <:filter
        field={@form[:group]}
        label="Group"
        type="combobox"
        options={MemberFilterViewModel.group_kinds(@team)}
        default=""
      />
    </.filter_bar>

    <.table
      :if={@awards != []}
      id={"#{@view}_awards"}
      rows={@awards}
      class="table-striped"
      row_class={&(@view == :all and MapSet.member?(@expired_ids, &1.id) and "is-muted")}
    >
      <:col :let={award} label="Member">
        <.member_cell
          member={award.member}
          team={@team}
          standing={@standings[award.member.id]}
          path={~p"/teams/#{@team}/members/#{award.member.id}/qualifications"}
        />
      </:col>
      <:col :let={award} label="Start" class="w-px whitespace-nowrap">
        <.date_cell value={award.starts_at} timezone={@team.timezone} />
      </:col>
      <:col :let={award} label="Expires" class="w-px whitespace-nowrap">
        <.expires_cell value={award.ends_at} timezone={@team.timezone} />
      </:col>
    </.table>
    <.empty_state
      :if={@awards == [] and filtered?(@filter_options)}
      id="no-matching-awards"
      title="No members match"
    >
      Change the search or the group.
    </.empty_state>
    <p :if={@awards == [] and !filtered?(@filter_options)} class="text-text-muted">
      {empty_text(@view)}
    </p>
    """
  end

  defp empty_text(:all), do: "No members hold it."
  defp empty_text(:active), do: "No members hold it now."
  defp empty_text(:expired), do: "No members have let it expire."

  defp filtered?(filter_options), do: filter_options.q not in [nil, ""] or filter_options.group

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
end
