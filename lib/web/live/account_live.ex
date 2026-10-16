defmodule Web.AccountLive do
  @moduledoc """
  Your settings, at /account: who you're logged in as, and the maps app place links open
  (#301). Team settings live under each team, so the URL names the team they change
  (#153); the account menu reaches them (#312).
  """

  use Web, :live_view_app_layout

  alias App.Operation.SetMapsApp
  alias Web.Components.OpenInMaps

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Your settings")}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Your settings</h1>
      <p id="account-email">
        Logged in as {@current_user.email}. Your email and your teams come from D4H.
      </p>
      <form id="maps-app-form" class="mt-8" phx-change="set-maps-app" phx-submit="set-maps-app">
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
