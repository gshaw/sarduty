defmodule App.Worker.NotifyTeamSignedUpWorker do
  @moduledoc """
  Tells the SAR Duty admins a team signed itself up (App.Operation.SignUpTeam), naming
  the member who did. Queued with the team, so the sign-up page never waits on it, and
  a refusal is tried again over a few hours.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Accounts
  alias App.Accounts.UserNotifier
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  @doc "Queues the notice. Call it in the transaction that makes the team."
  def enqueue(%Team{id: team_id}, %Member{id: member_id, team_id: team_id}),
    do: %{team_id: team_id, member_id: member_id} |> new() |> Oban.insert!()

  # After 30 minutes, an hour, then 90 minutes and 2 hours.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id, "member_id" => member_id}}) do
    with %Team{} = team <- Repo.get(Team, team_id),
         %Member{} = signer <- Repo.get_by(Member, id: member_id, team_id: team.id),
         {:ok, _email} <-
           UserNotifier.deliver_team_signed_up(Accounts.admin_emails(), team, signer.email) do
      :ok
    else
      nil -> {:cancel, "the team or its signer is gone"}
      {:error, reason} -> {:error, reason}
    end
  end
end
