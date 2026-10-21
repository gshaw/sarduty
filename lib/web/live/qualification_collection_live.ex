defmodule Web.QualificationCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  import Web.Components.FilterBar
  import Web.Components.ViewSwitch

  alias App.Adapter.D4H
  alias App.Model.GroupMember
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo
  alias App.ViewModel.MemberFilterViewModel
  alias App.ViewModel.QualificationFilterViewModel
  alias Service.StringHelpers

  @views ["all", "expiring"]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Qualifications")}
  end

  # `?view=expiring` lists each current member's qualifications that run out within the
  # next `within` days, 60 by default, the dashboard's "qualifications expire" link (#205).
  # `q` searches either view, and `group` keeps the expiring awards of a group's members.
  def handle_params(params, _uri, socket) do
    case QualificationFilterViewModel.validate(params, @views) do
      {:ok, filter_options, changeset} ->
        {:noreply, assign_lists(socket, filter_options, changeset)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp assign_lists(socket, filter_options, changeset) do
    current_team = socket.assigns.current_team
    q = filter_options.q || ""
    now = DateTime.utc_now()
    until = DateTime.add(now, filter_options.within, :day)
    qualifications = list_qualifications_with_counts(current_team)
    expiring = MemberQualificationAward.expiring(current_team.id, now, until)

    assign(socket,
      filter_options: filter_options,
      view: String.to_existing_atom(filter_options.view),
      q: q,
      form: to_form(changeset, as: "form"),
      all_count: length(qualifications),
      expiring_count: length(expiring),
      qualifications: Enum.filter(qualifications, &StringHelpers.matches?(&1.title, q)),
      expiring: filter_expiring(expiring, current_team, filter_options)
    )
  end

  defp filter_expiring(expiring, team, filter_options) do
    q = filter_options.q || ""
    group_member_ids = GroupMember.member_ids(team.id, filter_options.group)

    Enum.filter(
      expiring,
      &((StringHelpers.matches?(&1.member_name, q) or
           StringHelpers.matches?(&1.qualification, q)) and
          (is_nil(group_member_ids) or MapSet.member?(group_member_ids, &1.member_id)))
    )
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    params = Map.put(form_params, "view", socket.assigns.filter_options.view)

    case QualificationFilterViewModel.validate(params, @views) do
      {:ok, filter_options, _changeset} ->
        path = qualifications_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp count_text(:all, qualifications, _expiring),
    do:
      qualifications
      |> length()
      |> Service.Format.count(one: "%d qualification", many: "%d qualifications")

  defp count_text(:expiring, _qualifications, expiring),
    do:
      expiring
      |> length()
      |> Service.Format.count(
        one: "%d qualification expiring",
        many: "%d qualifications expiring"
      )

  defp qualifications_path(team, filter_options, changes \\ []) do
    params =
      filter_options
      |> struct(changes)
      |> QualificationFilterViewModel.query_params("all")

    ~p"/teams/#{team}/qualifications?#{params}"
  end

  def render(assigns) do
    ~H"""
    <div class="heading-row">
      <h1 class="title">{@page_title}</h1>
      <.button
        :if={D4H.records?(@current_team)}
        id="qualification-add"
        navigate={~p"/teams/#{@current_team}/qualifications/new"}
      >
        Add qualification
      </.button>
    </div>

    <.filter_bar
      for={@form}
      id="qualification_filter_form"
      count={count_text(@view, @qualifications, @expiring)}
      clear={qualifications_path(@current_team, %QualificationFilterViewModel{view: "#{@view}"})}
      path_fn={&qualifications_path(@current_team, @filter_options, &1)}
    >
      <:lead>
        <.view_switch label="Qualifications">
          <:view
            id="qualifications-all-link"
            patch={qualifications_path(@current_team, @filter_options, view: "all")}
            current={@view == :all}
            count={@all_count}
          >
            All
          </:view>
          <:view
            id="qualifications-expiring-link"
            patch={qualifications_path(@current_team, @filter_options, view: "expiring")}
            current={@view == :expiring}
            count={@expiring_count}
          >
            Expiring in {Service.Format.days(@filter_options.within)}
          </:view>
        </.view_switch>
      </:lead>
      <:search field={@form[:q]} />
      <:filter
        :if={@view == :expiring}
        field={@form[:group]}
        label="Group"
        type="combobox"
        options={MemberFilterViewModel.group_kinds(@current_team)}
        default=""
      />
      <:filter
        :if={@view == :expiring}
        field={@form[:within]}
        label="Within"
        options={QualificationFilterViewModel.within_kinds()}
        default={"#{QualificationFilterViewModel.default_within()}"}
      />
    </.filter_bar>

    <.expiring_table
      :if={@view == :expiring}
      team={@current_team}
      expiring={@expiring}
      none={@expiring_count == 0}
      within={@filter_options.within}
    />

    <.table
      :if={@view == :all and @qualifications != []}
      id="qualification_collection"
      rows={@qualifications}
      class="table-striped"
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

    <.empty_state
      :if={@view == :all and @all_count == 0}
      id="no-qualifications"
      title="No qualifications yet"
    >
      SAR Duty copies them from D4H when it refreshes.
    </.empty_state>
    <.empty_state
      :if={@view == :all and @all_count > 0 and @qualifications == []}
      id="no-matching-qualifications"
      title="No qualifications match"
    >
      Change the search.
    </.empty_state>
    <.empty_state
      :if={@view == :expiring and @expiring_count > 0 and @expiring == []}
      id="no-matching-qualifications"
      title="No expiring qualifications match"
    >
      Change the search or the filters.
    </.empty_state>
    """
  end

  attr :team, :map, required: true
  attr :expiring, :list, required: true
  attr :none, :boolean, required: true, doc: "nothing expires, before the search"
  attr :within, :integer, required: true, doc: "how many days ahead the view looks"

  defp expiring_table(assigns) do
    ~H"""
    <.table
      :if={@expiring != []}
      id="expiring_qualifications"
      rows={@expiring}
      row_id={&"expiring-#{&1.member_id}-#{&1.qualification_id}"}
      class="table-striped"
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
      <:col :let={row} label="Expires" align="right" class="w-1/12 whitespace-nowrap">
        {Service.Format.date_short(row.ends_at, @team.timezone)}
      </:col>
    </.table>
    <.empty_state :if={@none} id="none-expiring" title="Nothing expiring">
      No qualifications expire in the next {Service.Format.days(@within)}.
    </.empty_state>
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
