defmodule Web.PhotoAskLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.Member
  alias App.Model.PhotoAsk
  alias App.Operation.AskForPhoto
  alias App.Repo
  alias Service.Format

  # Ask for a photo (#1030): a team admin asks one member, or everyone with no photo, and
  # Photos and the member's ID Card tab show who was asked.
  setup %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{team: %{name: "Coast Range SAR", photos_enabled: true}})

    Member
    |> Repo.get_by!(team_id: team.id, email: user.email)
    |> Ecto.Changeset.change(name: "Alex Chen")
    |> Repo.update!()

    riley = member_fixture(team, %{name: "Riley Okafor", has_photo: false})
    %{conn: log_in_user(conn, user), user: user, team: team, riley: riley}
  end

  defp ask_path(team), do: ~p"/teams/#{team}/photos/members/ask"
  defp ask_path(team, member), do: ~p"/teams/#{team}/photos/members/ask?#{[member: member.id]}"
  defp card_path(team, member), do: ~p"/teams/#{team}/members/#{member.id}/card"

  defp ask(ctx, member, message \\ nil, now \\ DateTime.utc_now()) do
    {:ok, [ask]} = AskForPhoto.call(ctx.team, ctx.user, member, message, now)
    ask
  end

  describe "asking one member" do
    test "the page names them, takes a message, and its button counts who it reaches", ctx do
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.riley))

      assert has_element?(lv, "h1", "Ask for a photo")

      assert has_element?(
               lv,
               "#ask-lead",
               "Coast Range SAR emails each member a link to add a photo. It needs no login."
             )

      assert has_element?(lv, "#ask-to-#{ctx.riley.id}", "Riley Okafor")
      assert has_element?(lv, "#ask-to-#{ctx.riley.id}", ctx.riley.email)
      refute has_element?(lv, "#ask-left-out")
      assert has_element?(lv, ~s|label[for="ask-message"]|, "Message (optional)")
      assert has_element?(lv, "#ask-form .hint", "Your own words, at the top of the email.")
      assert has_element?(lv, ~s|#ask-message[maxlength="300"]|)
      assert has_element?(lv, ~s|#ask-send[phx-disable-with="Sending…"]|, "Ask 1 member")

      assert has_element?(
               lv,
               ~s|#ask-cancel[href="#{card_path(ctx.team, ctx.riley)}"]|,
               "Cancel"
             )
    end

    test "sending asks them, emails the message, and lands on their ID Card tab", ctx do
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.riley))

      {:ok, card, _html} =
        lv
        |> form("#ask-form", %{"message" => "The one we have has sunglasses."})
        |> render_submit()
        |> follow_redirect(ctx.conn, card_path(ctx.team, ctx.riley))

      assert render(card) =~ "1 member asked."
      assert %PhotoAsk{message: "The one we have has sunglasses."} = Repo.one!(PhotoAsk)

      assert_email_sent(fn email ->
        assert email.to == [{"Riley Okafor", ctx.riley.email}]
        assert email.text_body =~ "Alex Chen: “The one we have has sunglasses.”"
      end)

      today = Format.date_short(DateTime.utc_now(), ctx.team.timezone)
      assert has_element?(card, "#photo-asked", "Alex Chen asked on #{today}. No photo yet.")
      refute has_element?(card, "#photo-ask-failed")
    end

    test "a message too long says so, and nobody is asked", ctx do
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.riley))

      html = render_submit(lv, "send", %{"message" => String.duplicate("a", 301)})

      assert html =~ "Message must be 300 characters or fewer."
      assert Repo.all(PhotoAsk) == []
    end

    test "a member with a photo is asked for a new one, and one asked before is asked again",
         ctx do
      avery = member_fixture(ctx.team, %{name: "Avery Chen"})
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, avery))
      assert has_element?(lv, "#ask-send", "Ask 1 member")

      before = ask(ctx, ctx.riley, nil, ~U[2026-11-09 18:00:00.000000Z])
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, ctx.riley))
      assert has_element?(lv, "#ask-before", "Asked before, on Nov 9, 2026.")

      lv |> form("#ask-form") |> render_submit()
      assert DateTime.after?(Repo.reload!(before).asked_at, before.asked_at)
    end

    test "a member with no email cannot be asked, and the page says why", ctx do
      jordan = member_fixture(ctx.team, %{name: "Jordan Lee", has_photo: false, email: nil})
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team, jordan))

      assert has_element?(lv, "#ask-nobody", "Nobody to email now.")
      assert has_element?(lv, "#left-out-no_email", "No email: Jordan Lee.")
      refute has_element?(lv, "#ask-send")
      refute has_element?(lv, "#ask-message")
    end

    test "another team's member is not found", ctx do
      theirs = member_fixture(team_fixture(), %{has_photo: false})
      assert_error_sent 404, fn -> live(ctx.conn, ask_path(ctx.team, theirs)) end
    end
  end

  describe "asking everyone" do
    setup ctx do
      eli = member_fixture(ctx.team, %{name: "Eli Haddad", has_photo: false})
      jordan = member_fixture(ctx.team, %{name: "Jordan Lee", has_photo: false, email: nil})
      sam = member_fixture(ctx.team, %{name: "Sam Rivera", has_photo: false})
      member_fixture(ctx.team, %{name: "Avery Chen"})
      %{eli: eli, jordan: jordan, sam: sam}
    end

    test "the page lists who gets an email, and why the rest do not", ctx do
      ask(ctx, ctx.sam, nil, ~U[2026-11-09 18:00:00.000000Z])
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team))

      assert has_element?(lv, "h1", "Ask for photos")
      assert has_element?(lv, "#ask-to-#{ctx.eli.id}", "Eli Haddad")
      assert has_element?(lv, "#ask-to-#{ctx.riley.id}", "Riley Okafor")
      refute has_element?(lv, "#ask-to-#{ctx.sam.id}")
      refute has_element?(lv, "#ask-before")

      # Alex Chen, the team admin, and Avery Chen.
      assert has_element?(lv, "#left-out-has-photo", "Has a photo: 2 members.")
      assert has_element?(lv, "#left-out-no_email", "No email: Jordan Lee.")
      assert has_element?(lv, "#left-out-asked-0", "Asked Nov 9: Sam Rivera.")
      assert has_element?(lv, "#ask-send", "Ask 2 members")
      assert has_element?(lv, ~s|#ask-cancel[href="#{~p"/teams/#{ctx.team}/photos"}"]|)
    end

    test "sending asks each of them, and Photos shows the date under each", ctx do
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team))

      {:ok, photos, _html} =
        lv
        |> form("#ask-form")
        |> render_submit()
        |> follow_redirect(ctx.conn, ~p"/teams/#{ctx.team}/photos")

      assert render(photos) =~ "3 members asked."

      assert PhotoAsk |> Repo.all() |> Enum.map(& &1.member_id) |> Enum.sort() ==
               Enum.sort([ctx.eli.id, ctx.riley.id, ctx.sam.id])

      today = Format.month_day(DateTime.utc_now(), ctx.team.timezone)
      assert has_element?(photos, "#photo-#{ctx.eli.id}-asked", "Asked #{today}")
      refute has_element?(photos, "#photo-#{ctx.eli.id}-add")
      refute has_element?(photos, "#photo-#{ctx.eli.id}-ask")

      # Jordan was not asked, so their tile still offers both.
      assert has_element?(photos, "#photo-#{ctx.jordan.id}-add", "Add a photo")

      assert has_element?(
               photos,
               ~s|#photo-#{ctx.jordan.id}-ask[href="#{ask_path(ctx.team, ctx.jordan)}"]|,
               "Ask for a photo"
             )

      # Nobody is left to ask.
      {:ok, lv, _html} = live(ctx.conn, ask_path(ctx.team))
      assert has_element?(lv, "#ask-nobody", "Every member has a photo or has been asked.")
      refute has_element?(lv, "#ask-send")
    end
  end

  test "Photos has Ask for photos beside Add a photo", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/photos")
    assert has_element?(lv, ~s|#photo-ask[href="#{ask_path(ctx.team)}"]|, "Ask for photos")
  end

  test "the ID Card tab has Ask for a photo beside Add a photo, and Actions for a member with one",
       ctx do
    {:ok, lv, _html} = live(ctx.conn, card_path(ctx.team, ctx.riley))

    assert has_element?(
             lv,
             ~s|#no-photo #ask-photo[href="#{ask_path(ctx.team, ctx.riley)}"]|,
             "Ask for a photo"
           )

    refute has_element?(lv, "#photo-asked")
    refute has_element?(lv, "#member-actions-ask-photo")

    avery = member_fixture(ctx.team, %{name: "Avery Chen"})
    {:ok, lv, _html} = live(ctx.conn, card_path(ctx.team, avery))

    assert has_element?(
             lv,
             ~s|#member-actions-ask-photo[href="#{ask_path(ctx.team, avery)}"]|,
             "Ask for a photo"
           )
  end

  test "an email that never sent says so on the ID Card tab", ctx do
    ctx |> ask(ctx.riley) |> PhotoAsk.set_email_status!(:failed)
    {:ok, lv, _html} = live(ctx.conn, card_path(ctx.team, ctx.riley))
    assert has_element?(lv, "#photo-ask-failed", "The email did not send. Ask again.")
  end

  test "with Photos off the page is not found", ctx do
    ctx.team |> Ecto.Changeset.change(photos_enabled: false) |> Repo.update!()
    assert_error_sent 404, fn -> live(ctx.conn, ask_path(ctx.team)) end
  end

  test "a member cannot open it" do
    %{team: team, user: user} = member_with_login_fixture()
    team |> Ecto.Changeset.change(photos_enabled: true) |> Repo.update!()
    conn = log_in_user(build_conn(), user)
    assert_error_sent 404, fn -> live(conn, ask_path(team)) end
  end
end
