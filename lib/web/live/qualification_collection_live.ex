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

    Qualification
    |> where([q], q.team_id == ^team.id)
    |> join(:left, [q], mqa in MemberQualificationAward, on: mqa.qualification_id == q.id)
    |> group_by([q], [q.id, q.title])
    |> order_by([q], asc: q.title)
    |> select([q, mqa], %{
      id: q.id,
      title: q.title,
      total_count: count(mqa.id),
      active_count:
        fragment(
          "SUM(CASE WHEN (? IS NULL OR ? <= ?) AND (? IS NULL OR ? > ?) THEN 1 ELSE 0 END)",
          mqa.starts_at,
          mqa.starts_at,
          ^now,
          mqa.ends_at,
          mqa.ends_at,
          ^now
        ),
      expired_count:
        fragment(
          "SUM(CASE WHEN ? IS NOT NULL AND ? <= ? THEN 1 ELSE 0 END)",
          mqa.ends_at,
          mqa.ends_at,
          ^now
        )
    })
    |> Repo.all()
  end
end
