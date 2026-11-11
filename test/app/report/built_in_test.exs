defmodule App.Report.BuiltInTest do
  # The questions Members stopped asking as filters (#784 feedback): each a built-in report.
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Report
  alias App.Report.BuiltIn

  @now ~U[2026-06-15 19:00:00Z]

  defp rows(team, slug, params \\ %{}) do
    {:ok, view} = Report.page(BuiltIn.get(slug).query, team, params, @now)
    view.result.rows
  end

  defp ids(team, slug, params \\ %{}),
    do: team |> rows(slug, params) |> Enum.map(&hd/1) |> MapSet.new()

  # A team with a Retiring group, and `member` in it.
  defp retiring(team, member) do
    leavers = group_fixture(team, %{title: "Leavers"})
    group_member_fixture(leavers, member)

    team
    |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
    |> App.Repo.update!()
  end

  test "Hours in a tag counts only the activities with the tag, on this team" do
    team = team_fixture()
    tag_fixture(team, "Rope Rescue")
    rope = activity_fixture(team, %{started_at: ~U[2026-03-01 18:00:00Z], tags: ["Rope Rescue"]})

    other =
      activity_fixture(team, %{started_at: ~U[2026-03-08 18:00:00Z], tags: ["Primary Hours"]})

    avery = member_fixture(team, %{name: "Avery Rope", joined_at: ~U[2020-01-01 00:00:00Z]})
    blake = member_fixture(team, %{name: "Blake Ground", joined_at: ~U[2020-01-01 00:00:00Z]})
    attendance_fixture(rope, avery, %{duration_in_minutes: 180})
    attendance_fixture(other, avery, %{duration_in_minutes: 60})
    attendance_fixture(other, blake, %{duration_in_minutes: 60})

    # Another team's activity with the same tag counts for nothing here.
    other_team = team_fixture()

    attendance_fixture(
      activity_fixture(other_team, %{tags: ["Rope Rescue"]}),
      member_fixture(other_team)
    )

    rows = rows(team, "hours-in-a-tag", %{"tag" => "Rope Rescue"})
    assert [avery.id, 1, 180] in rows
    assert [blake.id, 0, 0] in rows
  end

  test "Members missing details names what each lacks, for current members" do
    team = team_fixture()
    no_phone = member_fixture(team, %{phone: nil})
    neither = member_fixture(team, %{phone: "", email: nil})
    no_address = member_fixture(team, %{address: ""})
    complete = member_fixture(team)
    retired = member_fixture(team, %{phone: nil, left_at: ~U[2025-01-01 00:00:00Z]})
    member_fixture(team_fixture(), %{phone: nil})

    missing =
      team |> rows("members-missing-details") |> Map.new(fn [id, _, text] -> {id, text} end)

    assert missing == %{
             no_phone.id => "Mobile phone",
             neither.id => "Mobile phone, Email",
             no_address.id => "Address"
           }

    refute Map.has_key?(missing, complete.id) or Map.has_key?(missing, retired.id)
  end

  test "Members holding items: who holds some, and, for Home's link, retiring members who hold none" do
    team = team_fixture()
    holding = member_fixture(team, %{name: "Holly Holding"})
    clear = member_fixture(team, %{name: "Clara Clear"})
    equipment_item_fixture(team, %{member_id: holding.id, status: "retired"})
    other_team = team_fixture()
    equipment_item_fixture(other_team, %{member_id: member_fixture(other_team).id})

    assert ids(team, "members-holding-items") == MapSet.new([holding.id])

    assert clear.id in ids(team, "members-holding-items", %{"items" => "none"})
    refute holding.id in ids(team, "members-holding-items", %{"items" => "none"})
  end

  test "Members holding items lists the retiring members who hold none, for Needs attention's link" do
    team = team_fixture()
    clear = member_fixture(team, %{name: "Clara Clear"})
    bot = member_fixture(team, %{name: "Pager", not_a_person: true})
    team = retiring(team, clear)
    params = %{"standing" => "retiring", "items" => "none"}

    assert ids(team, "members-holding-items", params) == MapSet.new([clear.id])
    refute bot.id in ids(team, "members-holding-items", %{"items" => "none"})
  end

  test "Members who can log in: who D4H lets log in, and who has No access" do
    team = team_fixture()
    can = member_fixture(team, %{name: "Cam Can", d4h_permission: 2})
    cannot = member_fixture(team, %{name: "Nell None", d4h_permission: 4})
    unknown = member_fixture(team, %{name: "Una Unknown", d4h_permission: nil})

    some = ids(team, "members-who-can-log-in")
    assert can.id in some
    refute cannot.id in some or unknown.id in some

    none = ids(team, "members-who-can-log-in", %{"access" => "none"})
    assert cannot.id in none
    refute can.id in none or unknown.id in none
  end

  test "Members who can log in lists the retiring members D4H still lets in, for Needs attention's link" do
    team = team_fixture()
    can = member_fixture(team, %{name: "Cam Can", d4h_permission: 2})
    bot = member_fixture(team, %{name: "Pager", not_a_person: true, d4h_permission: 2})
    team = retiring(team, can)
    params = %{"standing" => "retiring", "access" => "some"}

    assert ids(team, "members-who-can-log-in", params) == MapSet.new([can.id])
    refute bot.id in ids(team, "members-who-can-log-in")
  end

  test "Activities missing required fields keeps the past ones with a required field empty" do
    team = team_fixture()
    custom_field_fixture(team, %{d4h_custom_field_id: 454, required: true})
    past = %{activity_kind: "incident", started_at: ~U[2026-05-01 18:00:00Z]}
    missing = activity_fixture(team, Map.merge(past, %{custom_values: %{}}))
    activity_fixture(team, Map.merge(past, %{custom_values: %{"454" => "1"}}))

    activity_fixture(team, %{
      activity_kind: "incident",
      custom_values: %{},
      started_at: ~U[2026-07-01 18:00:00Z]
    })

    assert ids(team, "activities-missing-required-fields") == MapSet.new([missing.id])
  end
end
