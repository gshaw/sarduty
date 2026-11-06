defmodule App.Worker.SendMemberCardWorkerTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Operation.IssueEveryMemberCard
  alias App.Operation.SendMemberCard
  alias App.Worker.SendMemberCardWorker

  setup do
    team = team_fixture(%{every_member_card: true})
    member = member_fixture(team, %{name: "Cameron Ruiz", email: "cameron@example.com"})
    %{team: team, member: member}
  end

  defp perform(member, attempt \\ 1) do
    SendMemberCardWorker.perform(%Oban.Job{
      args: %{"team_id" => member.team_id, "member_id" => member.id},
      attempt: attempt,
      max_attempts: 5
    })
  end

  test "makes a card for a member with none and emails it, once", %{team: team, member: member} do
    assert perform(member) == :ok

    card = MemberCard.find_current(team, member)
    assert %MemberCard{email_status: :sent, emailed_at: %DateTime{}} = card
    assert_received {:email, %{to: [{"Cameron Ruiz", "cameron@example.com"}]} = email}
    assert email.text_body =~ MemberCard.format_code(card.code)

    # A second job finds the card sent and leaves it.
    assert perform(member) == :ok
    refute_received {:email, _}
    assert MemberCard.find_current(team, member).id == card.id
  end

  test "a member with no email still gets a card", %{team: team} do
    member = member_fixture(team, %{email: nil})

    assert perform(member) == :ok
    assert %MemberCard{email_status: nil} = MemberCard.find_current(team, member)
    refute_received {:email, _}
  end

  test "a refusal is tried again, and the last one marks the email failed",
       %{team: team, member: member} do
    card = member_card_fixture(member, %{email_status: :sending})
    refusing_mailer_fixture()

    assert {:error, _reason} = perform(member, 1)
    assert Repo.reload!(card).email_status == :sending

    assert {:error, _reason} = perform(member, 5)
    assert Repo.reload!(card).email_status == :failed
    assert MemberCard.find_current(team, member).id == card.id
  end

  test "an email removed before the job ran shows as failed", %{team: team} do
    member = member_fixture(team, %{email: nil})
    card = member_card_fixture(member, %{email_status: :sending})

    assert {:cancel, _reason} = perform(member)
    assert Repo.reload!(card).email_status == :failed
  end

  test "makes no card for a retiring member, or on a team with ID cards off",
       %{team: team, member: member} do
    leavers = group_fixture(team)
    team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
    group_member_fixture(leavers, member)

    assert {:cancel, :not_active} = perform(member)

    other = member_fixture(team)
    team |> Ecto.Changeset.change(id_cards_enabled: false) |> Repo.update!()
    assert {:cancel, :id_cards_off} = perform(other)

    assert MemberCard.find_current(team, member) == nil
    assert MemberCard.find_current(team, other) == nil
    refute_received {:email, _}
  end

  test "makes no card once Every member gets a card is off: a waiting job stops",
       %{team: team, member: member} do
    team = team |> Ecto.Changeset.change(every_member_card: false) |> Repo.update!()

    assert {:cancel, :every_member_card_off} = perform(member)
    assert MemberCard.find_current(team, member) == nil
    refute_received {:email, _}

    # A card made by Issue still gets its email.
    {:ok, card} = SendMemberCard.issue(team, member, DateTime.utc_now())
    assert_received {:email, _}
    assert Repo.reload!(card).email_status == :sent
  end

  test "one job per member while it waits, and a rollout can schedule it later",
       %{member: member} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      SendMemberCardWorker.enqueue(member, schedule_in: 30)
      SendMemberCardWorker.enqueue(member)

      assert [%Oban.Job{state: "scheduled"}] =
               all_enqueued(worker: SendMemberCardWorker, args: %{member_id: member.id})
    end)
  end

  # Only a click replaces a waiting job's time. A refresh during the rollout lines the
  # members up again, but each keeps the slot it had.
  test "a second rollout keeps each waiting job's slot, and only adds the new member's",
       %{team: team} do
    member_fixture(team, %{name: "Blake Morrison"})
    member_fixture(team, %{name: "Jordan Lee"})

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 3
      first = slots()
      assert Map.keys(first) == ["Blake Morrison", "Cameron Ruiz", "Jordan Lee"]
      gap = fn a, b -> DateTime.diff(first[b], first[a]) end
      assert gap.("Blake Morrison", "Cameron Ruiz") == 5
      assert gap.("Cameron Ruiz", "Jordan Lee") == 5

      # Avery sorts first, so this run asks for every slot 5 seconds later than before.
      member_fixture(team, %{name: "Avery Chen"})
      assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 4

      second = slots()
      assert Map.take(second, Map.keys(first)) == first
      assert Map.has_key?(second, "Avery Chen")
    end)
  end

  # Each waiting job's scheduled_at, by member name.
  defp slots do
    for job <- Repo.all(Oban.Job), into: %{} do
      {Repo.get!(Member, job.args["member_id"]).name, job.scheduled_at}
    end
  end

  # A click joins the member's waiting job (unique), so it moves that job to now (#893).
  test "Email card moves a job already waiting, a retry or a rollout slot, to now",
       %{team: team, member: member} do
    member_card_fixture(member, %{email_status: :sent})

    Oban.Testing.with_testing_mode(:manual, fn ->
      for state <- ["scheduled", "retryable"] do
        Repo.delete_all(Oban.Job)
        later = SendMemberCardWorker.enqueue(member, schedule_in: 30 * 60)
        later |> Ecto.Changeset.change(state: state) |> Repo.update!()
        now = DateTime.utc_now()

        assert {:ok, _card} = SendMemberCard.email(team, member, now)

        assert [%Oban.Job{id: id, state: ^state, scheduled_at: at}] = Repo.all(Oban.Job)

        assert id == later.id
        assert DateTime.compare(at, DateTime.add(now, 1, :second)) == :lt
      end
    end)
  end

  test "Email card sends the current card again", %{team: team, member: member} do
    card = member_card_fixture(member, %{email_status: :sent})

    assert {:ok, %MemberCard{}} = SendMemberCard.email(team, member, DateTime.utc_now())
    assert_received {:email, _}
    assert Repo.reload!(card).email_status == :sent
  end

  test "Replace makes a new code, stops the old one, and emails the new card",
       %{team: team, member: member} do
    old = member_card_fixture(member)

    assert {:ok, new} = SendMemberCard.issue(team, member, DateTime.utc_now())

    assert Repo.reload!(old).revoked_at
    refute new.code == old.code
    assert_received {:email, email}
    assert email.text_body =~ MemberCard.format_code(new.code)
    assert Repo.reload!(new).email_status == :sent
  end
end
