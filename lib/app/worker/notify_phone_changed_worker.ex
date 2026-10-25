defmodule App.Worker.NotifyPhoneChangedWorker do
  @moduledoc """
  Tells a member, at their email, that their mobile number changed (#156), in case
  someone else changed it. Queued with the change; nobody waits for it, and a refusal
  is tried again over a few hours. It names the number the member has when it runs.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Accounts.UserNotifier
  alias App.Model.Member
  alias App.Repo

  @doc "Queues the notice. Call it in the transaction that changes the number."
  def enqueue(%Member{id: id}), do: %{member_id: id} |> new() |> Oban.insert!()

  # After 30 minutes, an hour, then 90 minutes and 2 hours.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 30 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_id" => id}}) do
    case Member |> Repo.get(id) |> Repo.preload(:team) do
      %Member{email: email} = member when email not in [nil, ""] ->
        with {:ok, _email} <- UserNotifier.deliver_phone_changed(email, member.team, member.phone),
             do: :ok

      _gone_or_no_email ->
        {:cancel, "no member with an email"}
    end
  end
end
