defmodule Web.QualificationCollectionLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Qualifications")}
  end

  def handle_params(_params, _uri, socket) do
    current_team = socket.assigns.current_team
    qualifications = list_qualifications_with_counts(current_team)

    socket =
      socket
      |> assign(:qualifications, qualifications)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team} />
    <h1 class="title mb-p">{@page_title}</h1>

    <p class="mb-p text-secondary-1 text-sm">{length(@qualifications)} qualifications</p>

    <.table id="qualification_collection" rows={@qualifications} class="w-full table-striped">
      <:col :let={q} label="Qualification">
        <.a navigate={~p"/#{@current_team.subdomain}/qualifications/#{q.id}"}>{q.title}</.a>
      </:col>
      <:col :let={q} label="Active" class="w-px whitespace-nowrap" align="right">
        {q.active_count}
      </:col>
      <:col :let={q} label="Expired" class="w-px whitespace-nowrap" align="right">
        {q.expired_count}
      </:col>
      <:col :let={q} label="Total Awards" class="w-px whitespace-nowrap" align="right">
        {q.total_count}
      </:col>
    </.table>

    <p :if={@qualifications == []} class="text-secondary-1">No qualifications found.</p>
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
