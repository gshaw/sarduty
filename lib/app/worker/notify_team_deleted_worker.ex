defmodule App.Worker.NotifyTeamDeletedWorker do
  @moduledoc """
  Tells the SAR Duty admins a team was deleted (App.Operation.DeleteTeam), who did it,
  and where the database copy from just before is. The team is gone by the time it runs,
  so the job carries what the email names.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Accounts
  alias App.Accounts.User
  alias App.Accounts.UserNotifier
  alias App.Adapter.D4H
  alias App.Model.Team

  @doc "Queues the notice. Call it in the transaction that deletes the team."
  def enqueue(%Team{} = team, %User{email: email}, snapshot) do
    %{
      name: team.name,
      subdomain: team.subdomain,
      service: D4H.service_name(team),
      deleted_by: email,
      snapshot: snapshot
    }
    |> new()
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case UserNotifier.deliver_team_deleted(Accounts.admin_emails(), args) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
