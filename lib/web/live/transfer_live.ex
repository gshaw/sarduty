defmodule Web.TransferLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton

  alias App.Model.Member
  alias App.Model.Transfer
  alias App.Operation.CancelTransfer
  alias App.Repo
  alias Web.TransferText

  # A transfer code (#892), for the sending team's admins: the code to pass on, who made
  # it and where it stands, What will be transferred, and Cancel transfer while it works.
  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(%{"id" => id, "transfer_id" => transfer_id}, _uri, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(id) |> Repo.preload(:team)

    {:noreply,
     socket
     |> assign(:page_title, "#{member.name} · Transfer")
     |> assign(:member, member)
     |> assign_transfer(Transfer.find!(team, member, transfer_id))}
  end

  defp assign_transfer(socket, transfer) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()

    assign(socket,
      transfer: transfer,
      now: now,
      status: Transfer.status(transfer, now),
      made_by: Member.name_for_user(team, transfer.made_by_user, now),
      cancelled_by: Member.name_for_user(team, transfer.cancelled_by_user, now)
    )
  end

  def handle_event("cancel", _params, socket) do
    %{current_team: team, current_user: user, member: member, transfer: transfer} =
      socket.assigns

    socket =
      case CancelTransfer.call(team, transfer, user, DateTime.utc_now()) do
        {:ok, _transfer} -> put_flash(socket, :info, "Transfer cancelled.")
        {:error, _status} -> put_flash(socket, :error, "This code no longer works.")
      end

    {:noreply, assign_transfer(socket, Transfer.find!(team, member, transfer.id))}
  end

  def render(assigns) do
    assigns = assign(assigns, :first_name, Member.first_name(assigns.member))

    ~H"""
    <.breadcrumbs>
      <:item label="Members" path={~p"/teams/#{@current_team}/members"} />
      <:item label={@member.name} path={~p"/teams/#{@current_team}/members/#{@member.id}"} />
      <:item label="Transfer" />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <section id="transfer-code-section" class="measure">
      <p id="transfer-code" class={["heading font-mono mb-0", @status != :open && "text-text-muted"]}>
        <.copy_button
          :if={@status == :open}
          id="transfer-copy-code"
          text={Transfer.format_code(@transfer)}
          value={Transfer.format_code(@transfer)}
          label="Copy transfer code"
        />
        <span :if={@status != :open}>{Transfer.format_code(@transfer)}</span>
      </p>
      <p id="transfer-status" class="hint">
        {TransferText.status_line(
          @transfer,
          @made_by,
          @cancelled_by,
          @now,
          @current_team.timezone
        )}
      </p>
      <p :if={@status == :open} id="transfer-instructions">
        Give this code to a team admin at {@first_name}'s new team, or to {@first_name} to pass on. They enter it on {@first_name}'s page there.
      </p>
    </section>

    <section id="transfer-awards" class="mt-8 measure">
      <h2 class="heading">
        {heading(@status)}
      </h2>
      <ul class="list-disc pl-6">
        <li :for={award <- @transfer.awards} id={"transfer-award-#{award.id}"}>
          {TransferText.award(award, @now, @current_team.timezone)}
        </li>
      </ul>
    </section>

    <section :if={@status == :open} id="transfer-cancel-section" class="mt-8 measure">
      <.button
        id="transfer-cancel"
        type="button"
        variant={:danger}
        phx-click="cancel"
        phx-disable-with="Cancelling…"
        data-confirm="Cancel this transfer? The code stops working, and SAR Duty deletes its copy of the certificates."
      >
        Cancel transfer
      </.button>
      <p class="hint">The code stops working. SAR Duty deletes its copy of the certificates.</p>
    </section>
    """
  end

  defp heading(:open), do: "What will be transferred"
  defp heading(:used), do: "What was transferred"
  defp heading(_status), do: "What the code held"
end
