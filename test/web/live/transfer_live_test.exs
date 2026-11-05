defmodule Web.TransferLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Transfer
  alias App.Model.TransferAward
  alias App.Model.TransferAwardFile
  alias App.Operation.CancelTransfer
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{name: "Sam Rivera"})
    transfer = transfer_fixture(member, user)
    [award] = transfer.awards

    %{
      conn: log_in_user(conn, user),
      user: user,
      team: team,
      member: member,
      transfer: transfer,
      award: award,
      path: ~p"/teams/#{team}/members/#{member.id}/transfers/#{transfer.id}"
    }
  end

  test "shows the code, who made it, and what will be transferred", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "h1", "Sam Rivera · Transfer")
    assert has_element?(lv, "#transfer-code", Transfer.format_code(ctx.transfer))
    assert has_element?(lv, "#transfer-copy-code")
    assert has_element?(lv, "#transfer-status", "Made by Member ")
    assert has_element?(lv, "#transfer-status", "Works once, until")
    assert has_element?(lv, "#transfer-status", "Not used yet.")

    assert has_element?(
             lv,
             "#transfer-instructions",
             "Give this code to a team admin at Sam's new team"
           )

    assert has_element?(lv, "#transfer-awards h2", "What will be transferred")

    assert has_element?(
             lv,
             "#transfer-award-#{ctx.award.id}",
             "First aid, Jul 30, 2026 to Jul 30, 2029, with its certificate"
           )
  end

  test "any team admin cancels it: the code stops and the copied files go", ctx do
    other = App.AccountsFixtures.user_fixture()
    manager_fixture(ctx.team, %{email: other.email, name: "Alex Chen"})
    {:ok, lv, _html} = live(log_in_user(build_conn(), other), ctx.path)

    lv |> element("#transfer-cancel") |> render_click()

    transfer = Repo.get!(Transfer, ctx.transfer.id)
    assert Transfer.status(transfer, DateTime.utc_now()) == :cancelled
    assert transfer.cancelled_by_user_id == other.id
    assert TransferAwardFile.count_for_transfer(transfer) == 0
    # The award's line stays, so the page still says what the code held.
    assert Repo.get(TransferAward, ctx.award.id)

    assert render(lv) =~ "Transfer cancelled."
    assert has_element?(lv, "#transfer-status", "Cancelled by Alex Chen on")
    refute has_element?(lv, "#transfer-cancel")
    refute has_element?(lv, "#transfer-copy-code")
    refute has_element?(lv, "#transfer-instructions")
    assert has_element?(lv, "#transfer-awards h2", "What the code held")
  end

  test "an expired code says so, and cannot be cancelled", ctx do
    ctx.transfer
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :day))
    |> Repo.update!()

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "#transfer-status", "Expired on")
    refute has_element?(lv, "#transfer-cancel")
  end

  test "a code cancelled in another tab stays cancelled", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    {:ok, _} =
      CancelTransfer.call(ctx.team, ctx.transfer, ctx.user, DateTime.utc_now())

    lv |> element("#transfer-cancel") |> render_click()

    assert render(lv) =~ "This code no longer works."
    assert has_element?(lv, "#transfer-status", "Cancelled")
  end

  test "another member's or team's transfer is not found", ctx do
    other_member = member_fixture(ctx.team)

    assert_raise Ecto.NoResultsError, fn ->
      live(
        ctx.conn,
        ~p"/teams/#{ctx.team}/members/#{other_member.id}/transfers/#{ctx.transfer.id}"
      )
    end

    %{user: other_user, team: other_team} = user_with_team_fixture()
    other_team_member = member_fixture(other_team)

    assert_raise Ecto.NoResultsError, fn ->
      build_conn()
      |> log_in_user(other_user)
      |> live(
        ~p"/teams/#{other_team}/members/#{other_team_member.id}/transfers/#{ctx.transfer.id}"
      )
    end
  end

  test "a member cannot open it" do
    %{team: team, user: user, member: member} = member_with_login_fixture()
    conn = log_in_user(build_conn(), user)

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/members/#{member.id}/transfers/1")
    end
  end
end
