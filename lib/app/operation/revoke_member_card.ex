defmodule App.Operation.RevokeMemberCard do
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.UpdateCancelledCardWorker

  @doc """
  Stops the member's card from verifying. A job per card tells Wallet, so phones
  holding its pass fetch the voided one. The code is never reused.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, now) when team_id == team.id do
    {:ok, _cards} =
      Repo.transaction(fn ->
        team |> MemberCard.revoke_all!(member, now) |> UpdateCancelledCardWorker.enqueue_all()
      end)

    :ok
  end
end
