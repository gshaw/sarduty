defmodule Web.ActivityEmailMembersLiveTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest
  import App.DataFixtures
  import Ecto.Query

  alias App.Model.Member
  alias App.Model.Reminder
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{name: "Coast Range SAR"}})

    Member
    |> Repo.get_by!(team_id: team.id, email: user.email)
    |> Ecto.Changeset.change(name: "Alex Chen")
    |> Repo.update!()

    activity =
      activity_fixture(team, %{
        title: "Swiftwater training",
        started_at: DateTime.add(DateTime.utc_now(), 3, :day)
      })

    cameron = member_fixture(team, %{name: "Cameron Ruiz"})
    jordan = member_fixture(team, %{name: "Jordan Lee"})

    dana =
      team
      |> member_fixture(%{name: "Dana Clark"})
      |> Ecto.Changeset.change(invitation_reminders: false)
      |> Repo.update!()

    eli = member_fixture(team, %{name: "Eli Haddad", email: nil})
    avery = member_fixture(team, %{name: "Avery Chen"})
    quinn = member_fixture(team, %{name: "Quinn Laval"})

    for m <- [cameron, jordan, dana, eli],
        do: attendance_fixture(activity, m, %{status: "requested"})

    attendance_fixture(activity, avery, %{status: "attending"})
    attendance_fixture(activity, quinn, %{status: "absent"})

    # Cameron was emailed 2 days ago.
    Repo.insert!(%Reminder{
      team_id: team.id,
      activity_id: activity.id,
      member_id: cameron.id,
      sent_at: DateTime.add(DateTime.utc_now(), -2, :day),
      status: :sent
    })

    %{
      conn: log_in_user(conn, user),
      user: user,
      team: team,
      activity: activity,
      cameron: cameron,
      jordan: jordan
    }
  end

  defp path(ctx), do: ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/email"

  test "names who gets which email, and why everyone else gets none", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(lv, "h1", "Email members")
    assert has_element?(lv, "#email-to-#{ctx.cameron.id} td", "Oct ")
    refute has_element?(lv, "#email-to-#{ctx.jordan.id} td", "Oct ")
    assert has_element?(lv, "#email-select-#{ctx.jordan.id}[checked]")
    assert has_element?(lv, "#email-send", "Send 2 emails")

    assert has_element?(lv, "#left-out-replied", "1 signed up and 1 can't make it")
    assert has_element?(lv, "#left-out-reminders_off", "Dana Clark")
    assert has_element?(lv, "#left-out-no_email", "No email in D4H: Eli Haddad")
    refute has_element?(lv, "#email-to-table", "Avery Chen")
  end

  test "previews the email the mailer sends, with replies to the sender", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(lv, "#email-preview", "Will you be there? Swiftwater training")
    assert has_element?(lv, "#email-preview", "I'll be there")
    assert has_element?(lv, "#email-preview", "Can't make it")
    assert has_element?(lv, "#email-preview", "Alex Chen, a team admin, sent this email.")
    assert has_element?(lv, "#email-preview-section", "Replies come to you at #{ctx.user.email}")
    refute render(lv) =~ "/replies/"
  end

  test "the preview shows the message as it's typed, and the email carries it", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    refute has_element?(lv, "#email-preview", "Bring your rope kit.")

    lv
    |> form("#email-form")
    |> render_change(%{"member_ids" => ["#{ctx.jordan.id}"], "message" => "Bring your rope kit."})

    assert has_element?(lv, "#email-preview", "Bring your rope kit.")
    assert has_element?(lv, "#email-message", "Bring your rope kit.")
    assert has_element?(lv, "#email-send", "Send 1 email")

    lv
    |> form("#email-form")
    |> render_submit(%{"member_ids" => ["#{ctx.jordan.id}"], "message" => "Bring your rope kit."})

    assert_received {:email, %{to: [{"Jordan Lee", _}], text_body: text}}
    assert text =~ "Bring your rope kit."
  end

  test "sends only to the members still checked", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    lv |> form("#email-form") |> render_change(%{"member_ids" => ["#{ctx.cameron.id}"]})
    assert has_element?(lv, "#email-send", "Send 1 email")

    lv
    |> form("#email-form")
    |> render_submit(%{"member_ids" => ["#{ctx.cameron.id}"]})

    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
    assert_received {:email, %{to: [{"Cameron Ruiz", _}]}}
    refute_received {:email, _}

    assert [%Reminder{status: :sent}, %Reminder{status: :sent}] =
             Reminder |> where(member_id: ^ctx.cameron.id) |> Repo.all()
  end

  test "with nobody checked, the send button is off", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    # What the form sends once select all unchecks every box.
    render_change(lv, "change", %{})
    assert has_element?(lv, "#email-send[disabled]", "Send 0 emails")
  end

  test "once nobody is due, it says so", ctx do
    Repo.delete_all(App.Model.Attendance)
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(lv, "#email-nobody", "Nobody to email now.")
    refute has_element?(lv, "#email-send")
  end

  test "a started activity sends the visitor back", ctx do
    ctx.activity
    |> Ecto.Changeset.change(
      started_at: DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:error, {:live_redirect, %{to: to, flash: flash}}} = live(ctx.conn, path(ctx))
    assert to == ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}"
    assert flash["error"] == "Reminders closed when the activity started."
  end

  test "a deleted activity sends the visitor back", ctx do
    ctx.activity
    |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update!()

    assert {:error, {:live_redirect, %{to: to}}} = live(ctx.conn, path(ctx))
    assert to == ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}"
  end
end
