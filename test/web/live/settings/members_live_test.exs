defmodule Web.Settings.MembersLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.GroupRule
  alias App.Model.Team
  alias App.Operation.SaveTeamMemberSettings
  alias App.Repo

  test "saves the time frame for members who have not attended, or turns it off",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    assert team.not_seen_days == 90

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/settings/members")

    lv |> form("#member-settings-form", form: %{not_seen_days: "180"}) |> render_submit()
    assert Team.get!(team.id).not_seen_days == 180

    lv |> form("#member-settings-form", form: %{not_seen_days: "0"}) |> render_submit()
    assert Team.get!(team.id).not_seen_days == nil
  end

  test "saves the watched group and standings for the attendance check (#366)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    callout = group_fixture(team, %{title: "Callout"})
    assert team.watch_standings == ["active"]

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/members")

    assert has_element?(lv, "#watch-standing-active[checked]")

    lv
    |> form("#member-settings-form",
      form: %{watch_d4h_group_id: callout.d4h_group_id, watch_standings: ["", "active", "away"]}
    )
    |> render_submit()

    saved = Team.get!(team.id)
    assert saved.watch_d4h_group_id == callout.d4h_group_id
    assert saved.watch_standings == ["active", "away"]

    html =
      lv
      |> form("#member-settings-form", form: %{watch_d4h_group_id: "", watch_standings: [""]})
      |> render_submit()

    assert html =~ "Select at least one standing."
    assert Team.get!(team.id).watch_standings == ["active", "away"]
  end

  test "keeps a watched group D4H dropped, named as gone", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team |> Ecto.Changeset.change(watch_d4h_group_id: 424_242) |> Repo.update!()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/members")

    assert has_element?(
             lv,
             "select[name='form[watch_d4h_group_id]'] option[selected][value='424242']",
             "A deleted group"
           )
  end

  describe "the Retiring group (#514)" do
    test "offers only groups without rules, and saves one", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      leavers = group_fixture(team, %{title: "Leavers"})
      ruled = group_fixture(team, %{title: "Callout"})
      GroupRule.add!(ruled, :standing, :active)

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/members")

      refute has_element?(lv, "#watch-standing-retiring")
      assert has_element?(lv, "#form_retiring_d4h_group_id option", "Leavers")
      refute has_element?(lv, "#form_retiring_d4h_group_id option", "Callout")

      lv
      |> form("#member-settings-form", form: %{retiring_d4h_group_id: leavers.d4h_group_id})
      |> render_submit()

      assert Team.get!(team.id).retiring_d4h_group_id == leavers.d4h_group_id
      assert has_element?(lv, "#watch-standing-retiring")
    end

    test "refuses a group with rules" do
      %{team: team} = user_with_team_fixture()
      ruled = group_fixture(team, %{title: "Callout"})
      GroupRule.add!(ruled, :standing, :active)

      assert {:error, changeset} =
               SaveTeamMemberSettings.call(team, %{
                 "retiring_d4h_group_id" => "#{ruled.d4h_group_id}"
               })

      assert {"Select a group without rules.", _} = changeset.errors[:retiring_d4h_group_id]
    end

    test "keeps one D4H deleted, named as gone", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      team |> Ecto.Changeset.change(retiring_d4h_group_id: 424_242) |> Repo.update!()

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/members")

      assert has_element?(
               lv,
               "select[name='form[retiring_d4h_group_id]'] option[selected][value='424242']",
               "A deleted group"
             )
    end
  end

  describe "member fields (#681)" do
    alias App.Adapter.D4H
    alias App.Model.CustomField
    alias App.Operation.RefreshD4HData.UpsertCustomFields

    defp member_field(id, title, restricted),
      do: %D4H.CustomField{
        d4h_custom_field_id: id,
        title: title,
        target: "member",
        field_type: "text",
        restricted: restricted
      }

    test "offers unrestricted member fields and saves the picked ones", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      UpsertCustomFields.save(
        team.id,
        [member_field(630, "Radio Call Sign", false), member_field(855, "Date of Birth", true)],
        DateTime.utc_now()
      )

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/members")

      assert has_element?(lv, "#member-field-630")
      refute has_element?(lv, "#member-field-855")
      assert has_element?(lv, "#restricted-member-fields", "1 restricted field isn't offered.")

      lv |> form("#member-fields-form", %{"fields" => ["", "630"]}) |> render_submit()

      assert has_element?(lv, "#member-field-630[checked]")

      assert [%{d4h_custom_field_id: 630}] =
               team.id |> CustomField.get_all("member") |> Enum.filter(& &1.copy_values)
    end

    test "says when D4H has no member fields", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/members")

      assert has_element?(lv, "#no-member-fields")
      refute has_element?(lv, "#member-fields-form")
    end
  end
end
