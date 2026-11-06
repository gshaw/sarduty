defmodule Web.ActivityMembersLive.ActionTest do
  # Every choice on the Members tab by writing.md's Choices for checked rows (#920): each
  # hint with and without ticks, each greyed reason, and the pick moving off a greyed one.
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias Web.ActivityMembersLive.Absent
  alias Web.ActivityMembersLive.Action
  alias Web.ActivityMembersLive.Ask
  alias Web.ActivityMembersLive.Attended
  alias Web.ActivityMembersLive.Remove
  alias Web.ActivityMembersLive.RemoveBeforeStart
  alias Web.ActivityMembersLive.Update

  @starts ~U[2026-11-10 19:00:00Z]

  # 19:00 to midnight, an hour before the start and an hour after.
  @before_start %{
    activity: %Activity{started_at: @starts, finished_at: ~U[2026-11-11 00:00:00Z]},
    team: %Team{timezone: "Etc/UTC"},
    now: ~U[2026-11-10 18:00:00Z],
    retiring: MapSet.new()
  }
  @from_start %{@before_start | now: ~U[2026-11-10 20:00:00Z]}

  defp row(id, status, opts \\ []) do
    %Attendance{
      member_id: id,
      status: status,
      duration_in_minutes: opts[:minutes],
      member: %Member{
        id: id,
        name: "Member #{id}",
        email: Keyword.get(opts, :email, "m#{id}@example.com"),
        invitation_reminders: Keyword.get(opts, :reminders, true)
      }
    }
  end

  describe "before the start" do
    test "Ask for a reply counts who it asks and who replied" do
      checked = [row(1, "attending"), row(2, "requested"), row(3, "requested")]

      assert Ask.hint(@before_start, checked) ==
               "Emails “Will you be there?” to the 2 checked with no reply. 1 has replied."

      assert Ask.hint(@before_start, []) ==
               "Emails “Will you be there?” to the checked with no reply."

      assert Ask.unavailable(@before_start, checked) == nil
      assert Ask.count(@before_start, checked) == 2
      assert Ask.button_text(2) == "Ask 2 members"
      assert Ask.label() == "Ask for a reply"
    end

    test "Ask for a reply greys out when everyone checked has replied" do
      checked = [row(1, "attending"), row(2, "absent")]
      assert Ask.unavailable(@before_start, checked) == "Everyone checked has replied."
      assert Ask.unavailable(@before_start, []) == nil
    end

    test "Ask for a reply names who can't get one, and greys out when nobody can" do
      off = row(2, "requested", reminders: false)
      checked = [row(1, "requested"), off]

      assert Ask.hint(@before_start, checked) ==
               "Emails “Will you be there?” to the 1 checked with no reply. 1 with no reply can't get one."

      assert Ask.unavailable(@before_start, [off]) == "Nobody checked with no reply can get one."

      assert Ask.unavailable(%{@before_start | retiring: MapSet.new([1])}, [row(1, "requested")]) !=
               nil
    end

    test "Send an update says all checked get it and where they stand" do
      checked = [row(1, "attending"), row(2, "absent"), row(3, "requested")]

      assert Update.hint(@before_start, checked) ==
               "All 3 checked get your message and where they stand."

      assert Update.hint(@before_start, [row(1, "attending")]) ==
               "The 1 checked gets your message and where they stand."

      assert Update.hint(@before_start, []) ==
               "The checked get your message and where they stand."
    end

    test "Send an update names who has no email, and greys out when nobody has one" do
      checked = [row(1, "attending"), row(2, "absent", email: nil)]

      assert Update.hint(@before_start, checked) ==
               "1 of the 2 checked gets your message and where they stand. 1 has no email."

      assert Update.unavailable(@before_start, [row(2, "absent", email: nil)]) ==
               "Nobody checked has an email."
    end

    test "Remove from the activity says who gets the message" do
      some = [row(1, "attending"), row(2, "absent"), row(3, "requested")]

      assert RemoveBeforeStart.hint(@before_start, some) ==
               "All 3 checked come off the activity. The 1 who signed up gets your message."

      assert RemoveBeforeStart.hint(@before_start, [row(2, "absent"), row(3, "requested")]) ==
               "All 2 checked come off the activity. None signed up, so nobody is emailed."

      all = for id <- 1..6, do: row(id, "attending")

      assert RemoveBeforeStart.hint(@before_start, all) ==
               "All 6 checked come off the activity and get your message."

      assert RemoveBeforeStart.hint(@before_start, []) ==
               "The checked come off the activity. Those who signed up get your message."

      assert RemoveBeforeStart.unavailable(@before_start, some) == nil
    end
  end

  describe "from the start" do
    test "Mark attended gives the activity's times to who isn't attended" do
      checked = [row(1, "absent"), row(2, "attending"), row(3, "attending")]

      assert Attended.hint(@from_start, checked) ==
               "Gives the 1 checked the activity's times, 19:00 to 00:00. 2 attended already."

      assert Attended.hint(@from_start, []) ==
               "Gives the checked the activity's times, 19:00 to 00:00."

      assert Attended.unavailable(@from_start, [row(2, "attending")]) ==
               "Everyone checked attended already."

      assert Attended.label() == "Mark attended"
    end

    test "Mark absent names the hours that go" do
      checked = [
        row(1, "attending", minutes: 300),
        row(2, "attending", minutes: 270),
        row(3, "absent")
      ]

      assert Absent.hint(@from_start, checked) ==
               "The 2 attended lose their hours, 9h 30m. They stay on the activity. 1 is absent already."

      assert Absent.hint(@from_start, [row(4, "requested")]) ==
               "The 1 with no reply is marked absent. They stay on the activity."

      assert Absent.hint(@from_start, []) ==
               "The checked who attended lose their hours. They stay on the activity."

      assert Absent.unavailable(@from_start, [row(3, "absent")]) ==
               "Everyone checked is absent already."

      assert Absent.label() == "Mark absent"
    end

    test "Mark absent asks first when hours go, and names them" do
      activity = %{@from_start.activity | title: "Missing hiker"}
      ctx = %{@from_start | activity: activity}

      checked = [
        row(1, "attending", minutes: 270),
        row(2, "attending", minutes: 300),
        row(3, "absent")
      ]

      assert Absent.confirm(ctx, checked) == %{
               "data-confirm" =>
                 "Mark 2 members absent on Missing hiker? Their hours go, and Mark attended gives back the activity's times, not their own.",
               "data-confirm-warning" => "Member 1's 4h 30m and Member 2's 5 hours go."
             }

      assert Absent.confirm(ctx, [row(4, "requested"), row(3, "absent")]) == %{}
    end

    test "from 4 who attended, the confirm counts and totals, and from 10 waits on a box" do
      ctx = %{@from_start | activity: %{@from_start.activity | title: "Missing hiker"}}
      six = for id <- 1..6, do: row(id, "attending", minutes: 300)

      assert %{"data-confirm-warning" => "6 who attended lose 30 hours."} =
               confirm = Absent.confirm(ctx, six)

      refute Map.has_key?(confirm, "data-confirm-check")

      twelve = for id <- 1..12, do: row(id, "attending", minutes: 300)

      assert %{
               "data-confirm-warning" => "12 who attended lose 60 hours.",
               "data-confirm-check" => "I understand 12 members lose their hours."
             } = Absent.confirm(ctx, twelve)

      assert %{
               "data-confirm-warning" => "12 who attended lose 60 hours too.",
               "data-confirm-check" => "I understand 12 members come off the activity."
             } = Remove.confirm(ctx, twelve)

      three = for id <- 1..3, do: row(id, "attending", minutes: 300)

      assert Remove.confirm(ctx, three)["data-confirm-warning"] ==
               "Member 1's 5 hours, Member 2's 5 hours, and Member 3's 5 hours go too."
    end

    test "Send an update from the start is the message alone" do
      assert Update.hint(@from_start, [row(1, "attending"), row(2, "absent")]) ==
               "All 2 checked get your message."
    end

    test "Remove from the activity counts who loses hours" do
      checked = [row(1, "attending"), row(2, "attending"), row(3, "absent")]

      assert Remove.hint(@from_start, checked) ==
               "All 3 checked come off the activity, and 2 lose their hours. Add members puts them back, as attended."

      assert Remove.hint(@from_start, [row(3, "absent")]) ==
               "The 1 checked comes off the activity. Add members puts them back, as attended."

      assert Remove.hint(@from_start, []) ==
               "The checked come off the activity, and lose any hours. Add members puts them back, as attended."
    end
  end

  describe "pick/5" do
    @list [Attended, Absent, Update, Remove]

    test "keeps a choice that reaches someone" do
      assert Action.pick(@list, "absent", @from_start, [row(1, "attending")], false) == Absent
    end

    test "moves off a greyed choice to the next one offered" do
      attended = [row(1, "attending")]
      assert Action.pick(@list, "attended", @from_start, attended, false) == Absent
      assert Action.pick(@list, "absent", @from_start, [row(1, "absent")], false) == Update
    end

    test "with no choice, the first that reaches someone, or none from the start" do
      replied = [row(1, "attending")]
      before = [Ask, Update, RemoveBeforeStart]
      assert Action.pick(before, nil, @before_start, replied, true) == Update
      assert Action.pick(before, nil, @before_start, [], true) == Ask
      assert Action.pick(@list, nil, @from_start, replied, false) == nil
    end
  end
end
