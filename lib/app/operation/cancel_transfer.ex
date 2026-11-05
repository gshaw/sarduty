defmodule App.Operation.CancelTransfer do
  @moduledoc """
  A team admin's Cancel transfer (#892): the code stops working and SAR Duty deletes its
  copy of the certificates, in one transaction. Any team admin on the sending team can.
  """

  alias App.Accounts.User
  alias App.Model.Team
  alias App.Model.Transfer
  alias App.Model.TransferAwardFile
  alias App.Repo

  @doc "`{:ok, transfer}`, or `{:error, status}` when the code no longer works."
  def call(%Team{} = team, %Transfer{team_id: team_id} = transfer, %User{} = user, now)
      when team_id == team.id do
    Repo.transact(fn ->
      # Read again inside the transaction, so a code used or cancelled meanwhile stays so.
      current = Repo.get_by!(Transfer, id: transfer.id, team_id: team.id)

      case Transfer.status(current, now) do
        :open ->
          cancelled =
            current
            |> Ecto.Changeset.change(cancelled_at: now, cancelled_by_user_id: user.id)
            |> Repo.update!()

          TransferAwardFile.delete_for_transfer!(cancelled)
          {:ok, cancelled}

        status ->
          {:error, status}
      end
    end)
  end
end
