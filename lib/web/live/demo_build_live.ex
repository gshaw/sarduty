defmodule Web.DemoBuildLive do
  use Web, :live_view_narrow_layout

  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Operation.BuildDemoTeam
  alias App.Worker.BuildDemoTeamWorker

  # After the demo link logs the visitor in (#857): builds their copy of Coast Range SAR
  # the first time, behind a spinner, then opens its Dashboard. A built one opens at once.

  def mount(_params, _session, socket) do
    case DemoTeam.for_user(socket.assigns.current_user) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/demo")}

      %DemoTeam{team_id: team_id} when is_integer(team_id) ->
        {:ok, push_navigate(socket, to: ~p"/teams/#{Team.get!(team_id)}")}

      demo ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(App.PubSub, BuildDemoTeam.topic(demo))
          BuildDemoTeamWorker.enqueue(demo)
        end

        {:ok, assign(socket, page_title: "Building your demo", demo: demo, failed: false)}
    end
  end

  def render(assigns) do
    ~H"""
    <div :if={!@failed} id="demo-building">
      <h1 class="heading">Building your demo <.spinner /></h1>
      <p>
        Your own copy of Coast Range SAR, with a year of activities, members, and equipment.
        It takes a few seconds.
      </p>
    </div>
    <div :if={@failed} id="demo-failed">
      <h1 class="heading">Your demo did not build</h1>
      <p>Nothing was kept. Try again, and if it fails twice, try later.</p>
      <.form_actions>
        <.button id="demo-retry" variant={:success} phx-click="retry">Try again</.button>
      </.form_actions>
    </div>
    """
  end

  def handle_event("retry", _params, socket) do
    BuildDemoTeamWorker.enqueue(socket.assigns.demo)
    {:noreply, assign(socket, failed: false)}
  end

  def handle_info({:demo_built, _id, {:ok, team}}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/teams/#{team}")}

  def handle_info({:demo_built, _id, {:error, _reason}}, socket),
    do: {:noreply, assign(socket, failed: true)}
end
