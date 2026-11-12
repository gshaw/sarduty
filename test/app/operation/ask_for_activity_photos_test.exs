defmodule App.Operation.AskForActivityPhotosTest do
  use App.DataCase, async: true
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Model.Activity
  alias App.Model.ActivityPhotoAsk
  alias App.Model.Member
  alias App.Operation.AskForActivityPhotos
  alias App.Operation.AskForPhoto
  alias App.Operation.SetPhotoAsks
  alias App.Worker.SendPhotoAskWorker

  # cspell:ignore Noor -- Noor Aziz, of the Coast Range SAR cast
  @now ~U[2026-11-09 18:00:00.000000Z]

  defp activity(ctx), do: Activity.put_logged_minutes(ctx.activity)

  defp member(id, name, attrs \\ %{}),
    do: struct(%Member{id: id, name: name, email: "m#{id}@example.com"}, attrs)

  describe "plan/4" do
    test "did not attend, retiring, added photos, no email, and asks off are left out, with why" do
      members = [
        member(1, "Avery Chen"),
        member(2, "Eli Haddad"),
        member(3, "Jordan Lee", %{email: nil}),
        member(4, "Riley Okafor"),
        member(5, "Sam Rivera"),
        member(6, "Blank Email", %{email: ""}),
        member(7, "Noor Aziz", %{photo_asks: false}),
        member(8, "Cameron Ruiz")
      ]

      attended = MapSet.new([2, 3, 4, 5, 6, 7, 8])
      added = MapSet.new([4])
      retiring = MapSet.new([5])

      plan = AskForActivityPhotos.plan(members, attended, added, retiring)

      assert Enum.map(plan.send, & &1.name) == ["Eli Haddad", "Cameron Ruiz"]

      assert Enum.map(plan.left_out, &{&1.member.name, &1.reason}) == [
               {"Avery Chen", :not_attended},
               {"Jordan Lee", :no_email},
               {"Riley Okafor", :added},
               {"Sam Rivera", :retiring},
               {"Blank Email", :no_email},
               {"Noor Aziz", :asks_off}
             ]
    end

    test "the first reason that fits is the one given" do
      noor = member(7, "Noor Aziz", %{email: nil, photo_asks: false})
      one = MapSet.new([7])

      assert %{left_out: [%{reason: :not_attended}]} =
               AskForActivityPhotos.plan([noor], MapSet.new(), one, one)

      assert %{left_out: [%{reason: :retiring}]} =
               AskForActivityPhotos.plan([noor], one, one, one)

      assert %{left_out: [%{reason: :added}]} =
               AskForActivityPhotos.plan([noor], one, one, MapSet.new())

      assert %{left_out: [%{reason: :no_email}]} =
               AskForActivityPhotos.plan([noor], one, MapSet.new(), MapSet.new())
    end
  end

  describe "ActivityPhotoAsk.last/1" do
    test "the latest send, and how many members it asked" do
      earlier = ~U[2026-11-05 18:00:00.000000Z]

      asks = [
        %ActivityPhotoAsk{asked_at: earlier},
        %ActivityPhotoAsk{asked_at: @now},
        %ActivityPhotoAsk{asked_at: earlier},
        %ActivityPhotoAsk{asked_at: @now}
      ]

      assert ActivityPhotoAsk.last(asks) == %{count: 2, asked_at: @now}
      assert ActivityPhotoAsk.last([]) == nil
    end
  end

  describe "call/5" do
    setup do
      %{user: user, team: team} =
        user_with_team_fixture(%{team: %{name: "Coast Range SAR", photos_enabled: true}})

      Member
      |> Repo.get_by!(team_id: team.id, email: user.email)
      |> Ecto.Changeset.change(name: "Alex Chen")
      |> Repo.update!()

      activity =
        activity_fixture(team, %{
          title: "Swiftwater training",
          started_at: ~U[2026-11-04 03:00:00Z],
          finished_at: ~U[2026-11-04 05:30:00Z]
        })

      cam = member_fixture(team, %{name: "Cameron Ruiz"})
      attendance_fixture(activity, cam)
      %{user: user, team: team, activity: activity, cam: cam}
    end

    test "the ask and its job go in together, with ids as the job's args", ctx do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, [ask]} =
                 AskForActivityPhotos.call(
                   ctx.team,
                   activity(ctx),
                   ctx.user,
                   " Thanks!\r\n ",
                   @now
                 )

        assert %ActivityPhotoAsk{message: "Thanks!", asked_at: @now, email_status: :queued} = ask
        assert ask.member_id == ctx.cam.id
        assert ask.activity_id == ctx.activity.id
        assert ask.asked_by_user_id == ctx.user.id
        assert [%{args: args}] = all_enqueued(worker: SendPhotoAskWorker)
        assert args == %{"activity_photo_ask_id" => ask.id}
      end)
    end

    test "the email has the message, the Reply-To, and a link to Add photos for that activity and member",
         ctx do
      assert {:ok, [ask]} =
               AskForActivityPhotos.call(ctx.team, activity(ctx), ctx.user, "Thanks!", @now)

      assert_email_sent(fn email ->
        assert email.to == [{"Cameron Ruiz", ctx.cam.email}]
        assert email.from == {"SAR Duty", "noreply@sarduty.com"}
        assert email.reply_to == {"Coast Range SAR", ctx.user.email}
        assert email.subject == "Photos from Swiftwater training?"
        assert email.text_body =~ "Hi Cameron Ruiz,"

        # The activity's day on the team's clock: Nov 3 in Vancouver.
        assert email.text_body =~
                 "You were at Swiftwater training on Nov 3, 2026. Coast Range SAR would like your photos from it. A team admin looks at them before the team sees them."

        assert email.text_body =~ "Alex Chen: “Thanks!”"
        assert email.html_body =~ "Alex Chen: “Thanks!”"
        assert email.text_body =~ "Coast Range SAR, through SAR Duty"
        refute email.text_body =~ ~r/video/i

        [_all, token] = Regex.run(~r{Add photos:\n\S+/photos/activities/(\S+)}, email.text_body)
        assert email.html_body =~ "/photos/activities/#{token}"
        assert {:ok, found} = Web.PhotoAskLinks.find_activity_ask(token, DateTime.utc_now())
        assert found.id == ask.id
        assert found.member.id == ctx.cam.id
        assert found.activity.id == ctx.activity.id
      end)

      assert Repo.reload!(ask).email_status == :sent
    end

    test "a message over 300 characters asks nobody", ctx do
      long = String.duplicate("a", 301)

      assert AskForActivityPhotos.call(ctx.team, activity(ctx), ctx.user, long, @now) ==
               {:error, :message_too_long}

      assert Repo.all(ActivityPhotoAsk) == []
      assert_no_email_sent()
    end

    test "an incident or an activity still to start asks nobody", ctx do
      incident = activity_fixture(ctx.team, %{activity_kind: "incident"})
      attendance_fixture(incident, ctx.cam)
      coming = activity_fixture(ctx.team, %{started_at: DateTime.add(@now, 1, :day)})

      for activity <- [incident, coming] do
        activity = Activity.put_logged_minutes(activity)

        assert AskForActivityPhotos.call(ctx.team, activity, ctx.user, nil, @now) ==
                 {:error, :not_askable}
      end

      assert Repo.all(ActivityPhotoAsk) == []
    end

    test "asking again reaches whoever still has added none, on the same ask", ctx do
      noor = member_fixture(ctx.team, %{name: "Noor Aziz"})
      attendance_fixture(ctx.activity, noor)

      {:ok, first} = AskForActivityPhotos.call(ctx.team, activity(ctx), ctx.user, "First.", @now)
      assert length(first) == 2

      activity_photo_fixture(ctx.activity, %{member_id: noor.id})
      later = DateTime.add(@now, 3, :day)
      {:ok, [again]} = AskForActivityPhotos.call(ctx.team, activity(ctx), ctx.user, nil, later)

      assert again.member_id == ctx.cam.id
      assert again.id == Enum.find(first, &(&1.member_id == ctx.cam.id)).id
      assert %ActivityPhotoAsk{asked_at: ^later, message: nil} = Repo.reload!(again)
      assert length(Repo.all(ActivityPhotoAsk)) == 2
      assert AskForActivityPhotos.last_ask(ctx.activity) == %{count: 1, asked_at: later}
    end

    test "a member who turned photo asks off gets no email, and still gets an ask for a member photo",
         ctx do
      SetPhotoAsks.call(ctx.cam, false)

      assert {:ok, []} = AskForActivityPhotos.call(ctx.team, activity(ctx), ctx.user, nil, @now)
      assert_no_email_sent()

      # Turned off after the ask: its job sends nothing.
      ctx.cam |> Repo.reload!() |> SetPhotoAsks.call(true)

      {:ok, [ask]} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          AskForActivityPhotos.call(ctx.team, activity(ctx), ctx.user, nil, @now)
        end)

      ctx.cam |> Repo.reload!() |> SetPhotoAsks.call(false)
      assert {:cancel, _reason} = AskForActivityPhotos.deliver(ask.id, false, @now)
      assert_no_email_sent()

      # An ask for their ID card photo is not covered: the team needs that one.
      cam = Repo.reload!(ctx.cam)
      assert {:ok, [_ask]} = AskForPhoto.call(ctx.team, ctx.user, cam, nil, @now)
      assert_email_sent(subject: "Coast Range SAR needs a photo for your ID card")
    end

    test "the job sends nothing for an ask already sent, or one that is gone", ctx do
      {:ok, [ask]} = AskForActivityPhotos.call(ctx.team, activity(ctx), ctx.user, nil, @now)
      assert_email_sent()

      assert AskForActivityPhotos.deliver(ask.id, false, @now) == :ok
      assert_no_email_sent()

      Repo.delete!(ask)
      assert {:cancel, _reason} = AskForActivityPhotos.deliver(ask.id, false, @now)
    end
  end
end
