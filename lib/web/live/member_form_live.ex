defmodule Web.MemberFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.SaveMember
  alias App.ViewModel.MemberFormViewModel

  # Adding and changing members of a team on SAR Duty Records (docs/records.md), and
  # changing a member's details on a D4H team. D4H adds members and sets access in its
  # web app, so a D4H team's page has no Team admin box. The photo is Change photo's own
  # page, and retiring is on the Standing tab, on every team (#1053).
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    unless D4H.records?(team) or params["id"], do: raise(Web.Status.NotFound)

    member = if id = params["id"], do: team |> Member.find!(id) |> Map.put(:team, team)
    today = DateTime.utc_now() |> Service.Convert.utc_to_local(team.timezone) |> elem(0)
    form = MemberFormViewModel.from_member(member, team.timezone, today)

    socket =
      socket
      |> assign(page_title: if(member, do: "Change #{member.name}", else: "Add member"))
      |> assign(member: member, form_data: form)
      |> assign(records?: D4H.records?(team), roles: Member.roles(team))
      |> assign_form(MemberFormViewModel.changeset(form))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Members" path={~p"/teams/#{@current_team}/members"} />
      <:item
        :if={@member}
        label={@member.name}
        path={~p"/teams/#{@current_team}/members/#{@member.id}"}
      />
      <:item label={if @member, do: "Change", else: "Add member"} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form for={@form} id="member-form" phx-change="validate" phx-submit="save" class="measure">
      <.error_summary form={@form} />
      <.input field={@form[:name]} label="Name" />
      <div class="grid grid-cols-2 gap-x-6">
        <.input field={@form[:ref_id]} label="ID (optional)" />
        <.input
          field={@form[:position]}
          type="combobox"
          label="Role (optional)"
          options={@roles}
          free_text
        />
      </div>
      <.input field={@form[:email]} type="email" label="Email (optional)">
        Logging in to SAR Duty uses this email. Tax credit letters go to it too.
      </.input>
      <.input field={@form[:phone]} type="tel" label="Mobile phone (optional)" />
      <.input field={@form[:address]} type="textarea" rows="3" label="Address (optional)">
        For travel and tax credit letters.
      </.input>
      <%!-- Side by side only where a date fits in half the width. --%>
      <div class="grid md:grid-cols-2 gap-x-6">
        <.input field={@form[:joined_on]} type="date" label="Joined" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={MemberFormViewModel.statuses()}
        />
      </div>
      <.input :if={@records?} field={@form[:team_admin]} type="checkbox" label="Team admin">
        Team admins log in to SAR Duty and change the team's records.
      </.input>
      <.form_actions>
        <.button variant={:success} phx-disable-with={if @member, do: "Saving…", else: "Adding…"}>
          {if @member, do: "Save member", else: "Add member"}
        </.button>
        <.button
          id="member-cancel"
          navigate={
            if @member,
              do: ~p"/teams/#{@current_team}/members/#{@member.id}",
              else: ~p"/teams/#{@current_team}/members"
          }
        >
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"form" => params}, socket) do
    changeset =
      socket.assigns.form_data
      |> MemberFormViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case SaveMember.call(team, member, params, user, DateTime.utc_now()) do
      {:ok, saved} -> {:noreply, saved(socket, saved, "Saved #{params["name"]}.")}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  # The member page, or the list when the copy hasn't caught up yet.
  defp saved(socket, member, text) do
    team = socket.assigns.current_team

    path =
      if member, do: ~p"/teams/#{team}/members/#{member.id}", else: ~p"/teams/#{team}/members"

    socket |> put_flash(:info, text) |> push_navigate(to: path)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
