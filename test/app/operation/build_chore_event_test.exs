defmodule App.Operation.BuildChoreEventTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.AttendanceInfo
  alias App.Model.Chore
  alias App.Model.Member
  alias App.Operation.BuildChoreEvent

  @avery %Member{id: 1, d4h_member_id: 101, name: "Avery Chen"}
  @sam %Member{id: 2, d4h_member_id: 102, name: "Sam Rivera"}
  @event %{
    category: "Equipment maintenance",
    timezone: "America/Vancouver",
    tags: [%{d4h_tag_id: 7, title: "Primary Hours"}, %{d4h_tag_id: 8, title: "Chores"}]
  }
  # 00:00 on Oct 28, the last chore's day, in Vancouver.
  @start "2026-10-28T07:00:00Z"

  defp chore(id, member, minutes, date \\ ~D[2026-10-06]),
    do: %Chore{
      id: id,
      member: member,
      minutes: minutes,
      date: date,
      description: "Rope inspection"
    }

  defp actions(rows), do: Enum.map(rows, & &1.action)

  test "the first send makes the event on the last chore's day, tags it, adds each member's attendance, then publishes it" do
    chores = [
      chore(1, @sam, 60),
      chore(2, @avery, 180, ~D[2026-09-29]),
      chore(3, @sam, 180, ~D[2026-10-28])
    ]

    rows = BuildChoreEvent.plan(nil, chores, [], @event)

    assert actions(rows) == [
             :create_activity,
             :set_activity_tags,
             :create_attendance,
             :create_attendance,
             :publish_activity
           ]

    [create, tags, avery, sam, publish] = rows

    assert %{
             "kind" => "event",
             "title" => "Chores: Equipment maintenance, Sep 29 to Oct 28, 2026",
             "started_at" => @start,
             "finished_at" => "2026-10-28T11:00:00Z",
             "full_team" => false
           } = create.new_value

    refute Map.has_key?(create.new_value, "tag_ids")

    assert %{
             "created_in_set" => true,
             "tag_ids" => [7, 8],
             "titles" => ["Primary Hours", "Chores"]
           } = tags.new_value

    assert %{"d4h_member_id" => 101, "created_in_set" => true, "starts_at" => @start} =
             avery.new_value

    assert avery.new_value["ends_at"] == "2026-10-28T10:00:00Z"
    assert sam.new_value["ends_at"] == "2026-10-28T11:00:00Z"
    assert %{"created_in_set" => true, "published" => true} = publish.new_value
  end

  test "a changed chore changes its member's time, and only theirs" do
    current = [
      %AttendanceInfo{
        d4h_attendance_id: 501,
        d4h_member_id: 101,
        status: "attending",
        started_at: ~U[2026-10-28 07:00:00Z],
        finished_at: ~U[2026-10-28 10:00:00Z]
      },
      %AttendanceInfo{
        d4h_attendance_id: 502,
        d4h_member_id: 102,
        status: "attending",
        started_at: ~U[2026-10-28 07:00:00Z],
        finished_at: ~U[2026-10-28 08:00:00Z]
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
    assert update.new_value["finished_at"] == "2026-10-28T10:00:00Z"
    assert %{d4h_record_id: 502, member_id: 2} = sam
    assert sam.new_value["ends_at"] == "2026-10-28T09:00:00Z"
    assert %{d4h_record_id: 900, new_value: %{"published" => true}} = publish
  end

  test "with every chore declined, the event loses its attendance and stays a draft" do
    current = [
      %AttendanceInfo{d4h_attendance_id: 501, d4h_member_id: 101, status: "attending"},
      %AttendanceInfo{d4h_attendance_id: 503, d4h_member_id: 999, status: "attending"}
    ]

    rows = BuildChoreEvent.plan(%{d4h_activity_id: 900, published?: true}, [], current, @event)

    assert actions(rows) == [
             :publish_activity,
             :update_activity,
             :delete_attendance,
             :delete_attendance
           ]

    assert hd(rows).new_value == %{"published" => false}
    assert Map.keys(Enum.at(rows, 1).new_value) == ["description"]
    assert rows |> Enum.drop(2) |> Enum.map(& &1.d4h_record_id) == [501, 503]
  end

  test "someone added in D4H comes off when the event is sent again" do
    current = [%AttendanceInfo{d4h_attendance_id: 503, d4h_member_id: 999, status: "attending"}]
    state = %{d4h_activity_id: 900, published?: false}

    rows = BuildChoreEvent.plan(state, [chore(1, @avery, 30)], current, @event)

    assert actions(rows) == [
             :update_activity,
             :create_attendance,
             :delete_attendance,
             :publish_activity
           ]
  end

  test "a member's second row, added in D4H, comes off so their time counts once" do
    row = fn id ->
      %AttendanceInfo{
        d4h_attendance_id: id,
        d4h_member_id: 101,
        status: "attending",
        started_at: ~U[2026-10-06 07:00:00Z],
        finished_at: ~U[2026-10-06 07:30:00Z]
      }
    end

    state = %{d4h_activity_id: 900, published?: false}
    rows = BuildChoreEvent.plan(state, [chore(1, @avery, 30)], [row.(501), row.(502)], @event)

    assert actions(rows) == [:update_activity, :delete_attendance, :publish_activity]
    assert Enum.at(rows, 1).d4h_record_id == 502
  end

  test "nothing sent and no event in D4H plans nothing" do
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
