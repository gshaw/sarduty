defmodule Web.MeHoursLive do
  use Web, :live_view_app_layout

  import Web.Components.MeYear

  alias App.Model.Activity
  alias App.ViewData.MemberRecords

  # A member's primary and secondary hours for a year, /teams/:subdomain/me/hours,
  # counted as their tax credit letter counts them (docs/members.md).
  def mount(_params, _session, socket) do
    member = socket.assigns.member

    socket =
      socket
      |> assign(:years, MemberRecords.years(member, DateTime.utc_now()))
      |> assign(:hours_tags, Activity.hours_tags(member.team))

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    %{member: member, years: years} = socket.assigns
    year = year!(params["year"], years)

    socket =
      socket
      |> assign(:page_title, "Hours in #{year}")
      |> assign(:year, year)
      |> assign(:hours, MemberRecords.hours(member, year, DateTime.utc_now()))

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <div class="heading-row">
        <h1 class="title">Hours in {@year}</h1>
        <.year_switch years={@years} year={@year} path={~p"/teams/#{@member.team}/me/hours"} />
      </div>
      <dl id="hours">
        <dt>Primary hours</dt>
        <dd id="hours-primary">{Service.Format.duration(@hours.primary_minutes)}</dd>
        <dt>Secondary hours</dt>
        <dd id="hours-secondary">{Service.Format.duration(@hours.secondary_minutes)}</dd>
        <dt>Total</dt>
        <dd id="hours-total">{Service.Format.duration(@hours.total_minutes)}</dd>
      </dl>
      <p class="hint">
        Counted the same way as your tax credit letter. Only activities with the {@hours_tags.primary} or {@hours_tags.secondary} tag count.
      </p>
    </div>
    """
  end
end
