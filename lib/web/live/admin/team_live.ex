defmodule Web.Admin.TeamLive do
  use Web, :live_view_app_layout

  alias App.Operation.CreateHostedTeam
  alias App.ViewModel.HostedTeamViewModel

  # Creating a team without D4H (docs/hosted-d4h.md). Teams with D4H sign themselves up.
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "New team without D4H")
      |> assign_form(HostedTeamViewModel.build_new_changeset())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.back_link navigate={~p"/admin"}>Admin</.back_link>
    <h1 class="title">New team without D4H</h1>
    <p class="lead max-w-xl">
      SAR Duty keeps this team's members, activities, attendance, qualifications, and groups
      itself. A team with D4H signs up at {url(~p"/signup")} instead.
    </p>

    <.form for={@form} id="hosted-team-form" phx-change="validate" phx-submit="save" class="max-w-xl">
      <.input field={@form[:name]} label="Team name" />
      <.input field={@form[:subdomain]} label="Short name">
        In the team's address: {url(~p"/teams")}/{@form[:subdomain].value || "shortname"}. Lowercase
        letters, numbers, and dashes.
      </.input>
      <.input
        field={@form[:timezone]}
        type="select"
        label="Time zone"
        options={HostedTeamViewModel.timezones()}
      />
      <.input field={@form[:manager_name]} label="First manager's name" />
      <.input field={@form[:manager_email]} type="email" label="First manager's email">
        They log in with this email, and can make others managers.
      </.input>
      <.input
        field={@form[:sample_data]}
        type="checkbox"
        label="Add made-up members and activities to try it out"
      />
      <.form_actions>
        <.button variant={:success}>Create team</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"form" => params}, socket) do
    changeset =
      params
      |> HostedTeamViewModel.build_new_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case CreateHostedTeam.call(params) do
      {:ok, team} ->
        socket =
          socket
          |> put_flash(:info, "Created #{team.name}. Its manager can log in now.")
          |> push_navigate(to: ~p"/teams/#{team}")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
