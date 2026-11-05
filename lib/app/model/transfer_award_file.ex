defmodule App.Model.TransferAwardFile do
  use App, :model

  alias App.Model.Transfer
  alias App.Model.TransferAward
  alias App.Model.TransferAwardFile
  alias App.Repo

  # A transfer's copy of an award's certificate (#892), as the sending team's D4H sent it,
  # apart from the award so lists never load it. Deleted once the code is used,
  # cancelled, or expires.
  schema "transfer_award_files" do
    belongs_to :transfer_award, TransferAward
    field :bytes, :binary, redact: true
  end

  @doc "The award's copied file, or nil once it is gone."
  def bytes(%TransferAward{id: id}) do
    TransferAwardFile
    |> where(transfer_award_id: ^id)
    |> select([f], f.bytes)
    |> Repo.one()
  end

  @doc "Deletes every copied file of the transfer."
  def delete_for_transfer!(%Transfer{id: id}) do
    award_ids = from(a in TransferAward, where: a.transfer_id == ^id, select: a.id)

    TransferAwardFile
    |> where([f], f.transfer_award_id in subquery(award_ids))
    |> Repo.delete_all()

    :ok
  end

  @doc "How many copied files the transfer still has."
  def count_for_transfer(%Transfer{id: id}) do
    TransferAwardFile
    |> join(:inner, [f], a in assoc(f, :transfer_award))
    |> where([f, a], a.transfer_id == ^id)
    |> Repo.aggregate(:count)
  end
end
