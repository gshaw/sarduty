defmodule App.Worker.SendMemberCardWorkerTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures

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

  test "a rollout makes the card and the job emails it, once", %{team: team, member: member} do
    assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 1

    card = MemberCard.find_current(team, member)
    assert %MemberCard{email_status: :sent, emailed_at: %DateTime{}} = card
    assert_received {:email, %{to: [{"Cameron Ruiz", "cameron@example.com"}]} = email}
    assert email.text_body =~ MemberCard.format_code(card.code)

    # A second job finds the card sent and leaves it.
    assert perform(member) == :ok
    refute_received {:email, _}
    assert MemberCard.find_current(team, member).id == card.id
  end

  test "a member with no email still gets a card, and no job", %{team: team, member: member} do
    member_card_fixture(member)
    no_email = member_fixture(team, %{email: nil})

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 1
      assert %MemberCard{email_status: nil} = MemberCard.find_current(team, no_email)
      refute_enqueued(worker: SendMemberCardWorker)
    end)
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

  test "a rollout skips a retiring member, and makes none while ID cards are off",
       %{team: team, member: member} do
    leavers = group_fixture(team)
    team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
    group_member_fixture(leavers, member)

    assert team |> Repo.reload!() |> IssueEveryMemberCard.call(DateTime.utc_now()) == 0

    other = member_fixture(team)
    off = team |> Ecto.Changeset.change(id_cards_enabled: false) |> Repo.update!()
    assert IssueEveryMemberCard.call(off, DateTime.utc_now()) == 0

    assert MemberCard.find_current(team, member) == nil
    assert MemberCard.find_current(team, other) == nil
    refute_received {:email, _}
  end

  # Turning ID cards off cancels every card, so an email still waiting has nothing to send.
  test "a job whose card was cancelled sends nothing", %{member: member} do
    member_card_fixture(member, %{email_status: :sending, revoked_at: DateTime.utc_now()})

    assert {:cancel, "no card"} = perform(member)
    refute_received {:email, _}
  end

  test "a rollout makes every card at once and queues the emails behind any click",
       %{team: team} do
    member_fixture(team, %{name: "Blake Morrison"})
    member_fixture(team, %{name: "Jordan Lee"})

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 3

      assert MemberCard |> Repo.all() |> Enum.map(& &1.email_status) ==
               [:sending, :sending, :sending]

      jobs = Repo.all(Oban.Job)
      assert length(jobs) == 3
      assert Enum.all?(jobs, &(&1.state == "available" and &1.priority == 3))

      # Everyone has a card now, so a refresh during the rollout queues nothing more.
      assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 0
      assert length(Repo.all(Oban.Job)) == 3
    end)
  end

  # A click joins the member's waiting job (unique), so it moves that job to now and to
  # the front (#893).
  test "Email card moves a job already waiting, a retry or a rollout email, to now",
       %{team: team, member: member} do
    member_card_fixture(member, %{email_status: :sent})

    Oban.Testing.with_testing_mode(:manual, fn ->
      for state <- ["available", "scheduled", "retryable"] do
        Repo.delete_all(Oban.Job)
        later = SendMemberCardWorker.enqueue(member, schedule_in: 30 * 60, priority: 3)
        later |> Ecto.Changeset.change(state: state) |> Repo.update!()
        now = DateTime.utc_now()

        assert {:ok, _card} = SendMemberCard.email(team, member, now)

        assert [%Oban.Job{id: id, state: ^state, priority: 0} = job] = Repo.all(Oban.Job)
        assert id == later.id

        # An available job is due already; only a waiting one has a time to move.
        if state != "available",
          do: assert(DateTime.compare(job.scheduled_at, DateTime.add(now, 1, :second)) == :lt)
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
