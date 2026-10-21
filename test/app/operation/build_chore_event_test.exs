defmodule App.Operation.BuildChoreEventTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.AttendanceInfo
  alias App.Model.Chore
  alias App.Model.Member
  alias App.Operation.BuildChoreEvent

  @avery %Member{id: 1, d4h_member_id: 101, name: "Avery Chen"}
  @sam %Member{id: 2, d4h_member_id: 102, name: "Sam Rivera"}
  @event %{
    title: "Chores: Equipment maintenance, October 2026",
    month: ~D[2026-10-01],
    timezone: "America/Vancouver",
    tag_ids: [7, 8]
  }
  # 00:00 on Oct 31 in Vancouver.
  @start "2026-10-31T07:00:00Z"

  defp chore(id, member, minutes, date \\ ~D[2026-10-06]),
    do: %Chore{
      id: id,
      member: member,
      minutes: minutes,
      date: date,
      description: "Rope inspection"
    }

  defp actions(rows), do: Enum.map(rows, & &1.action)

  test "the first send makes the event, each member's attendance, then publishes it" do
    chores = [chore(1, @sam, 60), chore(2, @avery, 180), chore(3, @sam, 180)]

    rows = BuildChoreEvent.plan(nil, chores, [], @event)

    assert actions(rows) == [
             :create_activity,
             :create_attendance,
             :create_attendance,
             :publish_activity
           ]

    [create, avery, sam, publish] = rows

    assert %{
             "kind" => "event",
             "title" => "Chores: Equipment maintenance, October 2026",
             "started_at" => @start,
             "finished_at" => "2026-10-31T11:00:00Z",
             "tag_ids" => [7, 8],
             "full_team" => false
           } = create.new_value

    assert %{"d4h_member_id" => 101, "created_in_set" => true, "starts_at" => @start} =
             avery.new_value

    assert avery.new_value["ends_at"] == "2026-10-31T10:00:00Z"
    assert sam.new_value["ends_at"] == "2026-10-31T11:00:00Z"
    assert %{"created_in_set" => true, "published" => true} = publish.new_value
  end

  test "a late chore changes the member's time, and only theirs" do
    current = [
      %AttendanceInfo{
        d4h_attendance_id: 501,
        d4h_member_id: 101,
        status: "attending",
        started_at: ~U[2026-10-31 07:00:00Z],
        finished_at: ~U[2026-10-31 10:00:00Z]
      },
      %AttendanceInfo{
        d4h_attendance_id: 502,
        d4h_member_id: 102,
        status: "attending",
        started_at: ~U[2026-10-31 07:00:00Z],
        finished_at: ~U[2026-10-31 08:00:00Z]
      }
    ]

    chores = [chore(1, @avery, 180), chore(2, @sam, 60), chore(3, @sam, 60, ~D[2026-10-28])]
    state = %{d4h_activity_id: 900, published?: true}

    rows = BuildChoreEvent.plan(state, chores, current, @event)

    assert actions(rows) == [
             :publish_activity,
             :update_activity,
             :update_attendance,
             :publish_activity
           ]

    [unpublish, update, sam, publish] = rows
    assert unpublish.new_value == %{"published" => false}
    refute Map.has_key?(update.new_value, "tag_ids")
    assert update.new_value["finished_at"] == "2026-10-31T10:00:00Z"
    assert %{d4h_record_id: 502, member_id: 2} = sam
    assert sam.new_value["ends_at"] == "2026-10-31T09:00:00Z"
    assert %{d4h_record_id: 900, new_value: %{"published" => true}} = publish
  end

  test "a chore declined after it was accepted takes the member off; someone added in D4H goes too" do
    current = [
      %AttendanceInfo{d4h_attendance_id: 501, d4h_member_id: 101, status: "attending"},
      %AttendanceInfo{d4h_attendance_id: 503, d4h_member_id: 999, status: "attending"}
    ]

    rows =
      BuildChoreEvent.plan(%{d4h_activity_id: 900, published?: false}, [], current, @event)

    assert actions(rows) == [:update_activity, :delete_attendance, :delete_attendance]
    assert rows |> tl() |> Enum.map(& &1.d4h_record_id) == [501, 503]
  end

  test "a chore moved to another category is planned on each event as it is now" do
    moved_from = BuildChoreEvent.plan(%{d4h_activity_id: 900, published?: false}, [], [], @event)
    assert actions(moved_from) == [:update_activity]

    moved_to = BuildChoreEvent.plan(nil, [chore(1, @avery, 30)], [], @event)
    assert hd(moved_to).action == :create_activity
  end

  test "nothing accepted and no event in D4H plans nothing" do
    assert BuildChoreEvent.plan(nil, [], [], @event) == []
  end

  test "the description escapes what members wrote" do
    chores = [%{chore(1, %{@avery | name: "Avery <b>"}, 60) | description: "Fix <script>"}]

    [create | _rows] = BuildChoreEvent.plan(nil, chores, [], @event)
    description = create.new_value["description"]

    assert description =~ "Avery &lt;b&gt;"
    assert description =~ "Oct 6: Fix &lt;script&gt;, 1 hour"
    refute description =~ "<script>"
  end
end
