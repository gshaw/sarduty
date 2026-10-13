defmodule Web.AccountLive do
  @moduledoc """
  Your own page: who you're logged in as, each team's settings, and the maps app place
  links open (#301). Team settings live under each team, so the URL names the team they
  change (#153).
  """

  use Web, :live_view_narrow_layout

  alias App.Operation.SetMapsApp
  alias Web.Components.OpenInMaps

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Account")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="heading">Account</h1>
      <p id="account-email">
        Logged in as {@current_user.email}. Your email and your teams come from D4H.
      </p>
      <nav :if={@managed_teams != []} aria-label="Team settings">
        <h2 class="subheading">Team settings</h2>
        <ul class="action-list">
          <li :for={team <- @managed_teams}>
            <.a id={"account-team-#{team.id}-settings"} navigate={~p"/teams/#{team}/settings"}>
              {team.name}
            </.a>
          </li>
        </ul>
      </nav>
      <form id="maps-app-form" phx-change="set-maps-app">
        <fieldset>
          <legend class="subheading">Maps app</legend>
          <p class="hint">Places in SAR Duty open in this app.</p>
          <label
            :for={{app, name} <- [{"google", "Google Maps"}, {"apple", "Apple Maps"}]}
            class="choice"
          >
            <input
              type="radio"
              id={"maps-app-#{app}"}
              name="maps_app"
              value={app}
              checked={@current_user.maps_app == app}
            />
            {name}
          </label>
        </fieldset>
      </form>
    </div>
    """
  end

  def handle_event("set-maps-app", %{"maps_app" => app}, socket) do
    case SetMapsApp.call(socket.assigns.current_user, app) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> put_flash(:info, "Places now open in #{OpenInMaps.app_name(user.maps_app)}.")}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end
end
