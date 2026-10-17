defmodule Web.QualificationCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  import Web.Components.FilterBar
  import Web.Components.ViewSwitch

  alias App.Adapter.D4H
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo
  alias Service.StringHelpers

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Qualifications")}
  end

  # `?view=expiring` lists each current member's qualifications that run out in the next
  # 60 days, the dashboard's "qualifications expire" link (#205). `q` searches the view.
  def handle_params(params, _uri, socket) do
    current_team = socket.assigns.current_team
    view = view(params["view"])
    q = String.trim(params["q"] || "")
    now = DateTime.utc_now()
    until = DateTime.add(now, BuildGroupRulePreview.expiring_days(), :day)
    qualifications = list_qualifications_with_counts(current_team)
    expiring = MemberQualificationAward.expiring(current_team.id, now, until)

    {:noreply,
     assign(socket,
       view: view,
       q: q,
       form: to_form(%{"q" => q}, as: "form"),
       all_count: length(qualifications),
       expiring_count: length(expiring),
       qualifications: Enum.filter(qualifications, &StringHelpers.matches?(&1.title, q)),
       expiring:
         Enum.filter(
           expiring,
           &(StringHelpers.matches?(&1.member_name, q) or
               StringHelpers.matches?(&1.qualification, q))
         )
     )}
  end

  def handle_event("change", %{"form" => %{"q" => q}}, socket) do
    path = qualifications_path(socket.assigns.current_team, socket.assigns.view, q)
    {:noreply, push_patch(socket, to: path, replace: true)}
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

  defp view(nil), do: :all
  defp view("expiring"), do: :expiring
  defp view(_other), do: raise(Web.Status.NotFound)

  defp qualifications_path(team, view, q) do
    params =
      Enum.reject([view: view == :expiring && "expiring", q: q], &(elem(&1, 1) in [false, ""]))

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
      clear={qualifications_path(@current_team, @view, "")}
    >
      <:lead>
        <.view_switch label="Qualifications">
          <:view
            id="qualifications-all-link"
            patch={qualifications_path(@current_team, :all, @q)}
            current={@view == :all}
            count={@all_count}
          >
            All
          </:view>
          <:view
            id="qualifications-expiring-link"
            patch={qualifications_path(@current_team, :expiring, @q)}
            current={@view == :expiring}
            count={@expiring_count}
          >
            Expiring in {BuildGroupRulePreview.expiring_days()} days
          </:view>
        </.view_switch>
      </:lead>
      <:search field={@form[:q]} />
    </.filter_bar>

    <.expiring_table
      :if={@view == :expiring}
      team={@current_team}
      expiring={@expiring}
      none={@expiring_count == 0}
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
      :if={
        @all_count > 0 and @q != "" and if(@view == :all, do: @qualifications, else: @expiring) == []
      }
      id="no-matching-qualifications"
      title="No qualifications match"
    >
      Change the search.
    </.empty_state>
    """
  end

  attr :team, :map, required: true
  attr :expiring, :list, required: true
  attr :none, :boolean, required: true, doc: "nothing expires, before the search"

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
      No qualifications expire in the next {BuildGroupRulePreview.expiring_days()} days.
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
