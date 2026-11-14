defmodule Web.Settings.TeamContactsLive do
  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.SaveTeamContacts

  # Change team contacts, /teams/:subdomain/settings/contacts (#780, #1076): one or two
  # members Get help lists. General shows them and links here; Save and Cancel go back.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()
    changeset = team |> contacts_data(now) |> Team.build_contacts_changeset()

    socket =
      socket
      |> assign(page_title: "Change team contacts")
      |> assign(contact_choices: SaveTeamContacts.choices(team, now))
      |> assign_form(changeset)

    {:ok, socket}
  end

  # The saved contacts that still count, so one who left shows as None.
  defp contacts_data(team, now) do
    case Member.get_team_contacts(team, now) do
      [] -> %{team | first_contact_id: nil, second_contact_id: nil}
      [first] -> %{team | first_contact_id: first.id, second_contact_id: nil}
      [first, second] -> %{team | first_contact_id: first.id, second_contact_id: second.id}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, form: to_form(changeset, as: "contacts"))

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
      id="team-contacts-form"
      class="measure"
      phx-change="validate"
      phx-submit="save"
    >
      <p>
        One or two people members can ask for help. Get help lists them with their email and phone,
        and messages to the team go to them. They do not need to be team admins.
      </p>
      <.input
        :for={
          {field, label} <- [
            first_contact_id: "First contact",
            second_contact_id: "Second contact"
          ]
        }
        field={@form[field]}
        type="combobox"
        label={label}
        options={Enum.map(@contact_choices, &{&1.name, &1.id})}
        prompt="None"
        clearable
      />
      <.form_actions>
        <.button
          id="team-contacts-save"
          variant={:success}
          disabled={@viewing_as != nil}
          phx-disable-with="Saving…"
        >
          Save contacts
        </.button>
        <.button id="team-contacts-cancel" navigate={~p"/teams/#{@current_team}/settings"}>
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"contacts" => params}, socket) do
    changeset =
      socket.assigns.current_team
      |> Team.build_contacts_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"contacts" => params}, socket) do
    case SaveTeamContacts.call(socket.assigns.current_team, params) do
      {:ok, team} ->
        socket
        |> put_flash(:info, "Team contacts saved.")
        |> push_navigate(to: ~p"/teams/#{team}/settings")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
