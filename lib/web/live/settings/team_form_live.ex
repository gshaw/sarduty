defmodule Web.Settings.TeamFormLive do
  use Web, :live_view_app_layout

  alias App.Model.Team
  alias App.Operation.UpdateTeamSettings

  # Change team, /teams/:subdomain/settings/edit (#1076): the team's three names (#738)
  # and its address, which letters and forms print (#995). General shows them and links
  # here; Save team and Cancel go back. The place and time zone come from D4H, which
  # can't change them, so General only shows them.
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Change team")
      |> assign_form(Team.build_settings_changeset(socket.assigns.current_team))

    {:ok, socket}
  end

  defp assign_form(socket, %{} = source), do: assign(socket, :form, to_form(source, as: "form"))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={~p"/teams/#{@current_team}/settings"} />
      <:item label="General" path={~p"/teams/#{@current_team}/settings"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form
      for={@form}
      id="team_settings_form"
      class="measure"
      phx-submit="save"
      phx-change="validate"
    >
      <.error_summary form={@form} />
      <%!-- Three names for the room each place has (#738). --%>
      <p id="team-names-lead">
        Your team has three names, one for each amount of room. Each starts as your team's
        name.
      </p>
      <.input field={@form[:name]} label="Name">
        Used on most pages, emails, ID cards, and the phone top bar, which may cut off a
        name over {Service.Format.characters(Team.name_advice(:name))}.
      </.input>
      <.input field={@form[:legal_name]} label="Legal name">
        In full, as registered. Used on tax credit letters, the page that checks them, and
        the back of ID cards.
      </.input>
      <.input field={@form[:abbreviated_name]} label="Abbreviated name">
        Starts texts to members, where room is tight. {Service.Format.characters(
          Team.name_advice(:abbreviated_name)
        )} or fewer.
      </.input>
      <.input field={@form[:mailing_address]} label="Mailing address" type="textarea" rows="3">
        Where the CRA or an agency writes to your team. Tax credit letters and forms print it.
      </.input>
      <div class="grid md:grid-cols-2 gap-x-6">
        <.input field={@form[:city]} label="City (optional)" />
        <.input field={@form[:postal_code]} label="Postal code (optional)" />
      </div>
      <.form_actions>
        <.button id="team-save" variant={:success} phx-disable-with="Saving…">Save team</.button>
        <.button id="team-cancel" navigate={~p"/teams/#{@current_team}/settings"}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"form" => form_params}, socket) do
    changeset = Team.build_settings_changeset(socket.assigns.current_team, form_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    case UpdateTeamSettings.call(socket.assigns.current_team, form_params) do
      {:ok, team} ->
        socket
        |> put_flash(:info, "Team saved.")
        |> push_navigate(to: ~p"/teams/#{team}/settings")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
