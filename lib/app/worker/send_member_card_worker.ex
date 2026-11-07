defmodule App.Worker.SendMemberCardWorker do
  @moduledoc """
  Emails one member their current ID card (App.Operation.SendMemberCard.deliver/4) if it
  waits for its email. Issue, Replace, and Email card on the ID Card tab each queue one
  (#893), and Every member gets a card one per member, behind the clicks
  (App.Operation.IssueEveryMemberCard). A retry sends the email again; the last refusal
  marks the card's email failed, which the tab shows.

  Unique per member while it waits, so two queued close together send one email. A job
  already running doesn't count: a Replace while it sends still emails the new card.
  """

  use Oban.Worker,
    queue: :bulk,
    max_attempts: 5,
    unique: [
      keys: [:member_id],
      states: [:available, :scheduled, :retryable],
      period: :infinity
    ]

  alias App.Model.Member
  alias App.Operation.SendMemberCard

  @doc """
  Queues the member's card. Call it in the transaction that marks the card sending.
  `opts` go to the job, such as `priority: 3` for a rollout's.
  """
  def enqueue(%Member{id: id, team_id: team_id}, opts \\ []),
    do: %{team_id: team_id, member_id: id} |> new(opts) |> Oban.insert!()

  # After 10, 20, 30, then 40 minutes.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 10 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id, "member_id" => member_id}} = job) do
    SendMemberCard.deliver(
      team_id,
      member_id,
      job.attempt >= job.max_attempts,
      DateTime.utc_now()
    )
  end
end
