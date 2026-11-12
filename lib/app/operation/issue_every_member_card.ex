defmodule App.Operation.IssueEveryMemberCard do
  @moduledoc """
  Every member gets a card (#893): a team admin's switch on the Features tab, under ID
  cards. Turning it on makes a card, at once, for each member who needs one: counted (a
  person, not retiring), current, with a photo (#1012), and with no live card. Each with an email gets one
  App.Worker.SendMemberCardWorker job to email it. While it's on, each refresh and each
  sync that changed something does the same for members new since, through call/2.

  Making a card is database rows alone, and its email is a link to the card's page, which
  builds each pass when the member taps (#952). The `bulk` queue's limit of 2 paces the
  emails, and they run after any team admin's click, reminder, or letter
  (SendMemberCard's rollout priority).

  Off stops new cards. Emails already queued still go. Turning ID cards off turns this
  off too, and cancels every card, so a waiting email finds no card
  (App.Operation.SetTeamIdCards).
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.SendMemberCard
  alias App.Repo

  @doc """
  Turns the switch on or off. On makes a card for each member who needs one. `{:ok, team,
  made}`, or `{:error, :id_cards_off}` to turn it on while ID cards are off.
  """
  def set(%Team{} = team, enabled, %User{} = user, now) when is_boolean(enabled) do
    # Read again: the page's copy may predate a SAR Duty admin turning ID cards off.
    team |> Repo.reload!() |> set_fresh(enabled, user, now)
  end

  defp set_fresh(%Team{id_cards_enabled: false}, true, _user, _now), do: {:error, :id_cards_off}

  defp set_fresh(team, enabled, user, now) do
    Repo.transaction(fn ->
      team = team |> Ecto.Changeset.change(every_member_card: enabled) |> Repo.update!()
      made = call(team, now)
      kind = if enabled, do: :feature_turned_on, else: :feature_turned_off

      Event.record!(kind,
        team_id: team.id,
        user_id: user.id,
        data: %{feature: :every_member_card, made: made}
      )

      {team, made}
    end)
    |> then(fn {:ok, {team, made}} -> {:ok, team, made} end)
  end

  @doc """
  While the switch and ID cards are on, makes a card for each member who needs one and
  queues its email, and returns how many cards it made. One transaction: a rollout of
  100 is a few hundred small writes.
  """
  def call(%Team{every_member_card: true, id_cards_enabled: true} = team, now) do
    {:ok, made} =
      Repo.transaction(fn ->
        team
        |> waiting(now)
        |> Enum.count(&match?({:ok, _card}, SendMemberCard.issue_in_rollout(team, &1, now)))
      end)

    made
  end

  def call(%Team{}, _now), do: 0

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
  The members in good standing with a photo and no email, by name: they get a card, which
  they see on Your membership, but no email. The Features tab names them under the switch.
  """
  def without_email(%Team{} = team, now) do
    team
    |> counted_query(now)
    |> where([m], m.has_photo and (is_nil(m.email) or m.email == ""))
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  @doc """
  How many members would get a card but for a photo (#1012): counted, current, no live
  card, and no photo at the last check. The Features tab says so under the switch.
  """
  def count_without_photo(%Team{} = team, now) do
    team |> cardless_query(now) |> where([m], not m.has_photo) |> Repo.aggregate(:count)
  end

  # Counted and current members of the team with no live card and a photo, which a card
  # needs (IssueMemberCard).
  defp waiting(team, now) do
    team
    |> cardless_query(now)
    |> where([m], m.has_photo)
    |> order_by([m], asc: m.name, asc: m.id)
    |> Repo.all()
  end

  # Counted and current members of the team with no live card.
  defp cardless_query(team, now) do
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
