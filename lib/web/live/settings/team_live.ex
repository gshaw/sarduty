defmodule Web.Settings.TeamLive do
  alias App.Adapter
  use Web, :live_view_narrow_layout

  alias Adapter.D4H
  alias App.Model.Team

  def mount(_params, _session, socket) do
    team = socket.assigns.current_user.team

    socket =
      if team == nil do
        push_navigate(socket, to: ~p"/settings")
      else
        socket
        |> assign(page_title: "Team Settings")
        |> assign_form(Team.build_changeset(team))
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <p>
        <.a navigate={~p"/settings"}>← Settings</.a>
      </p>
      <h1 class="heading">Team settings</h1>

      <.form for={@form} phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} label="Name" />
        <div class="grid grid-cols-2 gap-h">
          <.input field={@form[:lat]} readonly label="Lat" class="bg-base-3" />
          <.input field={@form[:lng]} readonly label="Lng" class="bg-base-3" />
        </div>
        <.input field={@form[:timezone]} label="Timezone" readonly class="bg-base-3" />
        <.input
          field={@form[:mailing_address]}
          label="Mailing address"
          type="textarea"
          class="h-[10rem]"
        />
        <.form_actions>
          <.button class="btn-success">Save</.button>
          <:trailing>
            <.button type="button" phx-click="refresh">Refresh from D4H</.button>
          </:trailing>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "form"))
  end

  def handle_event("validate", %{"form" => form_params}, socket) do
    changeset = Team.build_changeset(socket.assigns.current_team, form_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    case Team.update(socket.assigns.current_team, form_params) do
      {:ok, _team} ->
        {:noreply, put_flash(socket, :info, "Changes saved")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:ok, d4h_team} = D4H.fetch_team(D4H.build_context(socket.assigns.current_user))
    {lat, lng} = d4h_team.coordinate

    params = %{
      name: d4h_team.name,
      lat: lat,
      lng: lng,
      timezone: d4h_team.timezone
    }

    case Team.update(socket.assigns.current_team, params) do
      {:ok, team} ->
        socket =
          socket
          |> assign_form(Team.build_changeset(team))
          |> put_flash(:info, "Refreshed from D4H")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
