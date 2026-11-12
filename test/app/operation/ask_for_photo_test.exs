defmodule App.Operation.AskForPhotoTest do
  use App.DataCase, async: true
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Model.Member
  alias App.Model.PhotoAsk
  alias App.Operation.AddOwnPhoto
  alias App.Operation.AskForPhoto
  alias App.Operation.CheckMemberPhoto
  alias App.Worker.SendPhotoAskWorker

  @now ~U[2026-11-09 18:00:00.000000Z]

  defp member(id, name, attrs \\ %{}),
    do: struct(%Member{id: id, name: name, email: "m#{id}@example.com"}, attrs)

  describe "plan/4" do
    setup do
      members = [
        member(1, "Avery Chen", %{has_photo: true}),
        member(2, "Eli Haddad"),
        member(3, "Jordan Lee", %{email: nil}),
        member(4, "Riley Okafor"),
        member(5, "Sam Rivera"),
        member(6, "Team Phone", %{not_a_person: true}),
        member(7, "Blank Email", %{email: ""})
      ]

      asked = %PhotoAsk{id: 9, member_id: 4, asked_at: @now}
      %{members: members, asked: asked, retiring: MapSet.new([5])}
    end

    test "everyone: a photo, no email, an open ask, retiring, and not a person are left out, with why",
         %{members: members, asked: asked, retiring: retiring} do
      plan = AskForPhoto.plan(members, [asked], retiring, :everyone)

      assert Enum.map(plan.send, &{&1.member.name, &1.ask}) == [{"Eli Haddad", nil}]

      assert Enum.map(plan.left_out, &{&1.member.name, &1.reason}) == [
               {"Avery Chen", :has_photo},
               {"Jordan Lee", :no_email},
               {"Riley Okafor", :asked},
               {"Sam Rivera", :retiring},
               {"Team Phone", :not_a_person},
               {"Blank Email", :no_email}
             ]

      # The ask comes with the member it leaves out, for its date.
      assert Enum.find(plan.left_out, &(&1.reason == :asked)).ask == asked
    end

    test "one member: a photo or an open ask does not stop a team admin asking", %{
      members: [avery, _eli, jordan, riley, sam, phone | _rest],
      asked: asked,
      retiring: retiring
    } do
      assert %{send: [%{member: ^avery, ask: nil}], left_out: []} =
               AskForPhoto.plan([avery], [asked], retiring, :one)

      assert %{send: [%{member: ^riley, ask: ^asked}], left_out: []} =
               AskForPhoto.plan([riley], [asked], retiring, :one)

      for {member, reason} <- [{jordan, :no_email}, {sam, :retiring}, {phone, :not_a_person}] do
        assert %{send: [], left_out: [%{reason: ^reason}]} =
                 AskForPhoto.plan([member], [asked], retiring, :one)
      end
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

      riley = member_fixture(team, %{name: "Riley Okafor", has_photo: false})
      %{user: user, team: team, riley: riley}
    end

    test "the ask and its job go in together, with ids as the job's args", ctx do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, [ask]} =
                 AskForPhoto.call(ctx.team, ctx.user, ctx.riley, " Sunglasses.\r\n ", @now)

        assert %PhotoAsk{message: "Sunglasses.", asked_at: @now, closed_at: nil} = ask
        assert ask.member_id == ctx.riley.id
        assert ask.asked_by_user_id == ctx.user.id
        assert ask.email_status == :queued
        assert_enqueued(worker: SendPhotoAskWorker, args: %{photo_ask_id: ask.id})
        assert [%{args: args}] = all_enqueued(worker: SendPhotoAskWorker)
        assert args == %{"photo_ask_id" => ask.id}
      end)
    end

    test "the email has the message, the Reply-To, and the link to Add a photo for that member",
         ctx do
      assert {:ok, [ask]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, "Sunglasses.", @now)

      assert_email_sent(fn email ->
        assert email.to == [{"Riley Okafor", ctx.riley.email}]
        assert email.from == {"SAR Duty", "noreply@sarduty.com"}
        assert email.reply_to == {"Coast Range SAR", ctx.user.email}
        assert email.subject == "Coast Range SAR needs a photo for your ID card"
        assert email.text_body =~ "Hi Riley Okafor,"

        assert email.text_body =~
                 "Coast Range SAR needs a new photo for your ID card. Take one with your phone: it takes a minute."

        assert email.text_body =~ "Alex Chen: “Sunglasses.”"
        assert email.html_body =~ "Alex Chen: “Sunglasses.”"
        assert email.text_body =~ "Coast Range SAR, through SAR Duty"

        [_all, token] = Regex.run(~r{Add a photo:\n\S+/photos/(\S+)}, email.text_body)
        assert email.html_body =~ "/photos/#{token}"
        assert {:ok, found} = Web.PhotoAskLinks.find_ask(token)
        assert found.id == ask.id
        assert found.member.id == ctx.riley.id
      end)

      assert Repo.reload!(ask).email_status == :sent
    end

    test "with no message the email has none", ctx do
      assert {:ok, [_ask]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, "  ", @now)

      assert_email_sent(fn email ->
        assert not (email.text_body =~ "Alex Chen")
        assert not (email.html_body =~ "“")
      end)
    end

    test "a message over 300 characters asks nobody", ctx do
      long = String.duplicate("a", 301)

      assert AskForPhoto.call(ctx.team, ctx.user, ctx.riley, long, @now) ==
               {:error, :message_too_long}

      assert Repo.all(PhotoAsk) == []
      assert_no_email_sent()
    end

    test "asking again moves the ask's date and sends another email", ctx do
      {:ok, [first]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, "First.", @now)
      later = DateTime.add(@now, 3, :day)
      {:ok, [again]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, nil, later)

      assert again.id == first.id
      assert %PhotoAsk{asked_at: ^later, message: nil} = Repo.reload!(again)
      assert [_one_row] = Repo.all(PhotoAsk)
      assert_email_sent(subject: "Coast Range SAR needs a photo for your ID card")
      assert_email_sent(subject: "Coast Range SAR needs a photo for your ID card")
    end

    test "everyone: each current member with no photo, an email, and no open ask", ctx do
      eli = member_fixture(ctx.team, %{name: "Eli Haddad", has_photo: false})
      member_fixture(ctx.team, %{name: "Jordan Lee", has_photo: false, email: nil})
      member_fixture(ctx.team, %{name: "Team Phone", has_photo: false, not_a_person: true})
      member_fixture(ctx.team, %{name: "Avery Chen"})

      member_fixture(ctx.team, %{
        name: "Gone Member",
        has_photo: false,
        left_at: DateTime.add(@now, -30, :day)
      })

      {:ok, [_riley]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, nil, @now)
      {:ok, asks} = AskForPhoto.call(ctx.team, ctx.user, :everyone, nil, @now)

      assert Enum.map(asks, & &1.member_id) == [eli.id]
      assert {:ok, []} = AskForPhoto.call(ctx.team, ctx.user, :everyone, nil, @now)
    end

    test "the job sends nothing for an ask that closed, or one already sent", ctx do
      {:ok, [ask]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, nil, @now)
      assert_email_sent()

      # Already sent: a job that runs twice sends one email.
      assert AskForPhoto.deliver(ask.id, false, @now) == :ok
      assert_no_email_sent()

      PhotoAsk.close_for_member(ctx.riley, @now)
      assert {:cancel, _reason} = AskForPhoto.deliver(ask.id, false, @now)
      assert_no_email_sent()
    end

    test "a member adding their photo closes the ask, and so does one found in the team's records",
         ctx do
      {:ok, [ask]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, nil, @now)
      assert AskForPhoto.open_for(ctx.team, ctx.riley, @now).asked_by == "Alex Chen"

      {:ok, taken} = 800 |> png_fixture(600) |> Service.MemberPhoto.prepare()
      {:ok, _waiting} = AddOwnPhoto.call(ctx.riley, taken, {0, %{x: 0.5, y: 0.5, side: 1.0}})

      assert Repo.reload!(ask).closed_at
      assert AskForPhoto.open_for(ctx.team, ctx.riley, @now) == nil

      # The night's check finds a photo added in the team's records.
      {:ok, [ask]} = AskForPhoto.call(ctx.team, ctx.user, ctx.riley, nil, @now)

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, png_fixture(10, 10))
      end)

      ctx.riley |> Repo.preload(:team) |> CheckMemberPhoto.call()
      assert Repo.reload!(ask).closed_at
    end
  end
end
