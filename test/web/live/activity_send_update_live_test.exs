defmodule Web.ActivitySendUpdateLiveTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest
  import App.DataFixtures

  alias App.Model.ActivityUpdate
  alias App.Model.Member
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

    avery = member_fixture(team, %{name: "Avery Chen"})
    quinn = member_fixture(team, %{name: "Quinn Laval"})
    cameron = member_fixture(team, %{name: "Cameron Ruiz"})

    dana =
      team
      |> member_fixture(%{name: "Dana Clark"})
      |> Ecto.Changeset.change(invitation_reminders: false)
      |> Repo.update!()

    eli = member_fixture(team, %{name: "Eli Haddad", email: nil})

    attendance_fixture(activity, avery, %{status: "attending"})
    attendance_fixture(activity, quinn, %{status: "absent"})
    for m <- [cameron, dana, eli], do: attendance_fixture(activity, m, %{status: "requested"})

    %{
      conn: log_in_user(conn, user),
      team: team,
      activity: activity,
      avery: avery,
      quinn: quinn,
      cameron: cameron,
      dana: dana
    }
  end

  defp path(ctx), do: ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/updates"

  test "lists everyone on the activity by reply, all checked", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(lv, "h1", "Send an update")
    assert has_element?(lv, "#update-to-attending", "Avery Chen")
    assert has_element?(lv, "#update-to-absent", "Quinn Laval")
    assert has_element?(lv, "#update-to-requested", "Cameron Ruiz")

    assert has_element?(
             lv,
             "#update-to-#{ctx.dana.id}",
             "Turned off reminders, so no reply buttons"
           )

    assert has_element?(lv, "#update-select-#{ctx.avery.id}[checked]")
    assert has_element?(lv, "#update-no-email", "Eli Haddad")
    assert has_element?(lv, "#update-send", "Send 4 emails")
    assert has_element?(lv, ~s(#update-send[data-confirm^="Email 4 members about"]))
    assert has_element?(lv, "#update-reminders-link")
  end

  test "the preview shows the message as it's typed, for each ending", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    assert has_element?(lv, "#email-preview", "Update: Swiftwater training")
    assert has_element?(lv, "#email-preview", "You're signed up.")
    refute has_element?(lv, "#email-preview", "Turn off invitation reminders")

    ids = Enum.map([ctx.avery, ctx.quinn, ctx.cameron, ctx.dana], &"#{&1.id}")

    lv
    |> form("#update-form")
    |> render_change(%{
      "member_ids" => ids,
      "message" => "Meet at the pullout.",
      "preview" => "ask"
    })

    assert has_element?(lv, "#email-preview", "Meet at the pullout.")
    assert has_element?(lv, "#email-preview", "I'll be there")

    lv
    |> form("#update-form")
    |> render_change(%{
      "member_ids" => ids,
      "message" => "Meet at the pullout.",
      "preview" => "open"
    })

    refute has_element?(lv, "#email-preview", "I'll be there")
  end

  test "sends to the members still checked, then lists the send", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    lv
    |> form("#update-form")
    |> render_submit(%{"member_ids" => ["#{ctx.quinn.id}"], "message" => "Meet at the pullout."})

    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
    assert_received {:email, %{to: [{"Quinn Laval", _}], subject: "Update: Swiftwater training"}}
    refute_received {:email, _}
    assert [%ActivityUpdate{status: :sent}] = Repo.all(ActivityUpdate)

    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    assert has_element?(lv, "#update-sent-before", "to 1 member")
    assert has_element?(lv, "#update-sent-before", "Meet at the pullout.")
  end

  test "with no message, nothing goes", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    html =
      lv
      |> form("#update-form")
      |> render_submit(%{"member_ids" => ["#{ctx.quinn.id}"], "message" => ""})

    assert html =~ "Enter a message."
    refute_received {:email, _}
  end

  test "a started activity sends the visitor back", ctx do
    ctx.activity
    |> Ecto.Changeset.change(
      started_at: DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:error, {:live_redirect, %{flash: flash}}} = live(ctx.conn, path(ctx))
    assert flash["error"] == "Updates closed when the activity started."
  end
end
