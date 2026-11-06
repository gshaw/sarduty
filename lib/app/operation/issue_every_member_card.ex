defmodule App.Operation.IssueEveryMemberCard do
  @moduledoc """
  Every member gets a card (#893): a team admin's switch on the Features tab, under ID
  cards. Turning it on queues one App.Worker.SendMemberCardWorker job per member who
  needs a card: counted (a person, not retiring), current, and with no live card. While
  it's on, each refresh and each sync that changed something does the same for members
  new since, through call/2.

  The jobs drip out, job n at (n - 1) × 5 seconds, so 40 cards take about 3 minutes.
  Each builds an Apple pass and a Google pass, and production is one shared CPU that
  throttles once its balance runs out (#584). OSS Oban has no rate limit, so the stagger
  is the throttle.

  Off stops new cards and cancels none: a waiting job then makes no card
  (SendMemberCard.deliver/4). Turning ID cards off turns this off too
  (App.Operation.SetTeamIdCards).
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.SendMemberCardWorker

  @stagger_seconds 5

  @doc """
  Turns the switch on or off. On queues a card for each member who needs one. `{:ok,
  team, queued}`, or `{:error, :id_cards_off}` to turn it on while ID cards are off.
  """
  def set(%Team{id_cards_enabled: false}, true, %User{}, _now), do: {:error, :id_cards_off}

  def set(%Team{} = team, enabled, %User{} = user, now) when is_boolean(enabled) do
    Repo.transaction(fn ->
      team = team |> Ecto.Changeset.change(every_member_card: enabled) |> Repo.update!()
      queued = call(team, now)
      kind = if enabled, do: :feature_turned_on, else: :feature_turned_off

      Event.record!(kind,
        team_id: team.id,
        user_id: user.id,
        data: %{feature: :every_member_card, queued: queued}
      )

      {team, queued}
    end)
    |> then(fn {:ok, {team, queued}} -> {:ok, team, queued} end)
  end

  @doc """
  While the switch and ID cards are on, queues a card for each member who needs one, and
  returns how many. A member whose job already waits keeps it (the job is unique per
  member).
  """
  def call(%Team{every_member_card: true, id_cards_enabled: true} = team, now) do
    members = waiting(team, now)

    members
    |> schedule()
    |> Enum.each(fn {member, seconds} ->
      SendMemberCardWorker.enqueue(member, schedule_in: seconds)
    end)

    length(members)
  end

  def call(%Team{}, _now), do: 0

  @doc """
  Pure. When each member's job runs, in seconds from now: the first at once, then one
  every #{@stagger_seconds} seconds.
  """
  def schedule(members),
    do: members |> Enum.with_index() |> Enum.map(fn {m, n} -> {m, n * @stagger_seconds} end)

  @doc """
  Pure. What turning the switch on would do, for its confirm: `cards` made, `emails`
  sent, and `no_email`, the members who get a card with no email.
  """
  def plan(members) do
    no_email = Enum.count(members, &no_email?/1)
    %{cards: length(members), emails: length(members) - no_email, no_email: no_email}
  end

  @doc "plan/1 for the members who need a card now."
  def preview(%Team{} = team, now), do: team |> waiting(now) |> plan()

  @doc """
  The members in good standing with no email, by name: they get a card, which they see on
  Your membership, but no email. The Features tab names them under the switch.
  """
  def without_email(%Team{} = team, now) do
    team
    |> counted_query(now)
    |> where([m], is_nil(m.email) or m.email == "")
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  defp waiting(team, now),
    do: team |> waiting_query(now) |> order_by([m], asc: m.name, asc: m.id) |> Repo.all()

  # Counted and current members of the team with no live card.
  defp waiting_query(team, now) do
    carded =
      MemberCard
      |> where([c], c.team_id == ^team.id and is_nil(c.revoked_at))
      |> select([c], c.member_id)

    team |> counted_query(now) |> where([m], m.id not in subquery(carded))
  end

  defp counted_query(team, now) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> Member.counted_query()
    |> Member.current_query(now)
  end

  defp no_email?(%Member{email: email}), do: email in [nil, ""]
end
