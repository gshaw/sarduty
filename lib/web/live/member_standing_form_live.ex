defmodule Web.MemberStandingFormLive do
  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Operation.AddAwayPeriod
  alias App.Operation.RecordCheckIn

  # Add an away period (:away) and Record a check-in (:check_in), each its own page from
  # the member's Standing tab (#1053), so the tab reads as the member's standing. Both
  # go back to the tab. AddAwayPeriod and RecordCheckIn refuse a retired member or a bot,
  # whose tab has no button for either.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(id) |> Map.put(:team, team)
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    {:ok, socket |> assign(member: member, today: today) |> assign_form()}
  end

  defp assign_form(%{assigns: %{live_action: :away}} = socket) do
    %{member: member, today: today} = socket.assigns
    changeset = MemberAwayPeriod.build_changeset(%MemberAwayPeriod{starts_on: today})

    assign(socket,
      page_title: "Add an away period for #{member.name}",
      crumb: "Add away period",
      form: to_form(changeset, as: "away")
    )
  end

  defp assign_form(%{assigns: %{live_action: :check_in}} = socket) do
    %{member: member, today: today} = socket.assigns
    changeset = MemberCheckIn.build_changeset(%MemberCheckIn{checked_in_on: today}, %{}, today)

    assign(socket,
      page_title: "Record a check-in with #{member.name}",
      crumb: "Record check-in",
      form: to_form(changeset, as: "check_in")
    )
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Members" path={~p"/teams/#{@current_team}/members"} />
      <:item label={@member.name} path={~p"/teams/#{@current_team}/members/#{@member.id}"} />
      <:item label="Standing" path={standing_path(@current_team, @member)} />
      <:item label={@crumb} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form
      :if={@live_action == :away}
      for={@form}
      id="away-form"
      phx-change="validate"
      phx-submit="save"
      class="measure"
    >
      <.error_summary form={@form} />
      <div class="grid md:grid-cols-2 gap-x-6">
        <.input field={@form[:starts_on]} type="date" label="First day" />
        <.input field={@form[:ends_on]} type="date" label="Last day" />
      </div>
      <.input field={@form[:reason]} label="Reason" maxlength="60">
        For example, Parental leave or Moving. Leave out medical details.
      </.input>
      <.form_actions>
        <.button variant={:success} phx-disable-with="Adding…">Add away period</.button>
        <.button id="away-cancel" navigate={standing_path(@current_team, @member)}>Cancel</.button>
      </.form_actions>
    </.form>

    <.form
      :if={@live_action == :check_in}
      for={@form}
      id="check-in-form"
      phx-change="validate"
      phx-submit="save"
      class="measure"
    >
      <.error_summary form={@form} />
      <.input field={@form[:checked_in_on]} type="date" label="Day you reached them" />
      <.input field={@form[:note]} type="textarea" label="What you heard (optional)" />
      <.form_actions>
        <.button variant={:success} phx-disable-with="Recording…">Record check-in</.button>
        <.button id="check-in-cancel" navigate={standing_path(@current_team, @member)}>
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", params, socket) do
    changeset =
      socket
      |> build_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: socket.assigns.form.name))}
  end

  def handle_event("save", params, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    result =
      case socket.assigns.live_action do
        :away -> AddAwayPeriod.call(team, member.id, user, params["away"])
        :check_in -> RecordCheckIn.call(team, member.id, user, params["check_in"])
      end

    case result do
      {:ok, _record} ->
        {:noreply, back(socket, :info, saved_text(socket.assigns.live_action))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: socket.assigns.form.name))}

      # No button leads here for them; this is a page left open while someone changed it.
      :not_a_person ->
        {:noreply, back(socket, :error, "#{member.name} is not a person. Nothing was added.")}

      :retired ->
        {:noreply, back(socket, :error, "#{member.name} is retired. Nothing was added.")}
    end
  end

  defp build_changeset(%{assigns: %{live_action: :away}}, params),
    do: MemberAwayPeriod.build_changeset(%MemberAwayPeriod{}, params["away"])

  defp build_changeset(%{assigns: %{live_action: :check_in, today: today}}, params),
    do: MemberCheckIn.build_changeset(%MemberCheckIn{}, params["check_in"], today)

  defp saved_text(:away), do: "Away period added."
  defp saved_text(:check_in), do: "Check-in recorded."

  defp back(socket, kind, text) do
    %{current_team: team, member: member} = socket.assigns
    socket |> put_flash(kind, text) |> push_navigate(to: standing_path(team, member))
  end

  defp standing_path(team, member), do: ~p"/teams/#{team}/members/#{member.id}/standing"
end
