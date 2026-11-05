defmodule Web.TransferFormLive do
  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Model.Transfer
  alias App.Operation.MakeTransfer
  alias App.Repo
  alias Service.Format
  alias Web.TransferText

  # Transfer to another team (#892), for team admins only: a retiring member's page has it
  # too. The member's latest award of each qualification, expired ones unchecked. Make
  # transfer code copies the checked ones from the team's D4H now, then opens the code.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(id) |> Repo.preload(:team)
    now = DateTime.utc_now()
    rows = MakeTransfer.offered(member, now)

    {:ok,
     assign(socket,
       page_title: "#{member.name} · Transfer to another team",
       member: member,
       rows: rows,
       selected: rows |> Enum.reject(&(&1.status == :expired)) |> MapSet.new(& &1.award.id),
       open: Transfer.open_for_member(member, now),
       now: now
     )}
  end

  def handle_event("change", params, socket) do
    selected =
      params
      |> Map.get("award_ids", [])
      |> Enum.flat_map(fn id ->
        case Integer.parse(id) do
          {id, ""} -> [id]
          _ -> []
        end
      end)
      |> MapSet.new()

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("make", params, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns
    {:noreply, socket} = handle_event("change", params, socket)
    award_ids = MapSet.to_list(socket.assigns.selected)

    case MakeTransfer.call(team, member, award_ids, user, DateTime.utc_now()) do
      {:ok, transfer} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transfer code made.")
         |> push_navigate(to: ~p"/teams/#{team}/members/#{member.id}/transfers/#{transfer.id}")}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  def render(assigns) do
    assigns = assign(assigns, :first_name, Member.first_name(assigns.member))

    ~H"""
    <.breadcrumbs>
      <:item label="Members" path={~p"/teams/#{@current_team}/members"} />
      <:item label={@member.name} path={~p"/teams/#{@current_team}/members/#{@member.id}"} />
      <:item label="Transfer to another team" />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p class="lead measure">
      Make a code for a team admin at {@first_name}'s new team. They add the awards you select, with their certificates, to {@first_name}'s record there.
    </p>

    <ul :if={@open != []} id="transfer-open" class="measure mb-6">
      <li :for={transfer <- @open}>
        {@first_name} has a code that still works: <.a
          id={"transfer-open-#{transfer.id}"}
          navigate={~p"/teams/#{@current_team}/members/#{@member.id}/transfers/#{transfer.id}"}
        >{Transfer.format_code(transfer)}</.a>.
      </li>
    </ul>

    <p :if={@rows == []} id="transfer-no-awards">
      {@member.name} has no qualifications to transfer.
    </p>

    <.form :if={@rows != []} for={%{}} id="transfer-form" phx-change="change" phx-submit="make">
      <%!-- Sent with nothing checked, so unchecking the last one clears the selection. --%>
      <input type="hidden" name="award_ids[]" value="" />
      <.table id="transfer-awards" rows={@rows} row_id={&"transfer-award-#{&1.award.id}"}>
        <:col :let={row} label="" class="w-px" select_all>
          <input
            type="checkbox"
            id={"transfer-select-#{row.award.id}"}
            name="award_ids[]"
            value={row.award.id}
            checked={MapSet.member?(@selected, row.award.id)}
          />
        </:col>
        <:col :let={row} label="Qualification">
          <label for={"transfer-select-#{row.award.id}"}>
            <.qualification_cell
              qualification={row.award.qualification}
              team={@current_team}
              link={false}
            />
          </label>
          <.badge :if={row.status == :expired} kind={:warning}>Expired</.badge>
        </:col>
        <:col :let={row} label="Dates" class="whitespace-nowrap">
          {TransferText.dates(row.award, @current_team.timezone)}
        </:col>
        <:col :let={row} label="Certificate" class="w-px whitespace-nowrap">
          {if row.award.d4h_document_id, do: "Certificate", else: "None"}
        </:col>
      </.table>
      <p class="hint">Expired awards are left out unless you select them.</p>

      <.form_actions class="mt-8">
        <.button
          id="transfer-make"
          variant={:success}
          disabled={MapSet.size(@selected) == 0}
          phx-disable-with="Making code…"
        >
          Make transfer code
        </.button>
        <.button navigate={~p"/teams/#{@current_team}/members/#{@member.id}"}>Cancel</.button>
      </.form_actions>
      <p class="hint measure">
        The code works once, for {Format.days(Transfer.days_open())}. {@current_team.name} keeps {@first_name}'s record as it is.
      </p>
    </.form>
    """
  end
end
