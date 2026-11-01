defmodule App.Operation.RemoveMembersTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AttendanceStub
  alias App.Model.ActivityUpdate
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Operation.RemoveMembers

  defp member(id, attrs \\ %{}),
    do:
      struct(
        %Member{
          id: id,
          d4h_member_id: 100 + id,
          name: "Member #{id}",
          email: "m#{id}@example.com"
        },
        attrs
      )

  defp row(member, id, status),
    do: %Attendance{id: id, member_id: member.id, d4h_attendance_id: 900 + id, status: status}

  describe "plan/4" do
    test "each member goes with all their rows, each with its own status (K)" do
      jordan = member(1)
      rows = [row(jordan, 1, "attending"), row(jordan, 2, "requested")]

      assert {:ok, %{remove: [entry], not_removed: []}} =
               RemoveMembers.plan([{jordan, "attending"}], rows, "Sorry")

      assert entry.email?

      assert [
               %ChangeSetRow{action: :delete_attendance, d4h_record_id: 901, reason: "Sorry"} =
                 first,
               %ChangeSetRow{d4h_record_id: 902} = second
             ] = RemoveMembers.rows([entry], "Sorry")

      assert first.old_value == %{"d4h_member_id" => 101, "status" => "attending"}
      assert second.old_value == %{"d4h_member_id" => 101, "status" => "requested"}
    end

    test "a reply changed since the page opened is left out, and a member with no row" do
      eli = member(1)
      quinn = member(2)

      assert {:ok, %{remove: [], not_removed: not_removed}} =
               RemoveMembers.plan(
                 [{eli, "requested"}, {quinn, "requested"}],
                 [row(eli, 1, "attending")],
                 nil
               )

      assert not_removed == [{eli, :changed}, {quinn, :gone}]
    end

    test "a message only when a signed up member gets an email (option 2)" do
      drew = member(1)
      sam = member(2, email: nil)
      harper = member(3)

      assert {:error, :no_message} =
               RemoveMembers.plan([{drew, "attending"}], [row(drew, 1, "attending")], nil)

      # Sam has no email, and Harper never replied: neither needs one.
      assert {:ok, %{remove: [%{email?: false}, %{email?: false}]} = plan} =
               RemoveMembers.plan(
                 [{sam, "attending"}, {harper, "requested"}],
                 [row(sam, 1, "attending"), row(harper, 2, "requested")],
                 nil
               )

      assert plan.remove |> RemoveMembers.rows(nil) |> Enum.all?(&(&1.reason == nil))
    end

    # The exception: they were told already. The message still goes to History.
    test "with no email, a signed up member still needs the message, as the reason" do
      drew = member(1)
      rows = [row(drew, 1, "attending")]

      assert {:error, :no_message} = RemoveMembers.plan([{drew, "attending"}], rows, nil, false)

      assert {:ok, %{remove: [%{message?: true, email?: false}] = remove}} =
               RemoveMembers.plan([{drew, "attending"}], rows, "Told them", false)

      assert [%ChangeSetRow{reason: "Told them"}] = RemoveMembers.rows(remove, "Told them")
    end
  end

  test "result_text names who gets the email and each member not removed (L)" do
    drew = member(1, name: "Drew Patel")
    eli = member(2, name: "Eli Haddad")
    quinn = member(3, name: "Quinn Laval")

    assert RemoveMembers.result_text(%{
             removed: [drew, member(4), member(5), member(6)],
             emailed: [drew],
             not_removed: [{eli, :changed}, {quinn, "D4H did not answer. Try again."}]
           }) ==
             "4 members removed. Drew Patel gets your email. " <>
               "Eli Haddad was not removed: their reply changed since you opened the page. Review again. " <>
               "Quinn Laval was not removed: D4H did not answer. Try again."

    assert RemoveMembers.result_text(%{removed: [], emailed: [], not_removed: [{eli, :gone}]}) ==
             "Nobody was removed. Eli Haddad was off the activity already."
  end

  describe "call/7" do
    setup do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
      now = DateTime.utc_now()
      starts = now |> DateTime.add(3, :day) |> DateTime.truncate(:second)

      activity =
        activity_fixture(team, %{started_at: starts, finished_at: DateTime.add(starts, 3, :hour)})

      drew = member_fixture(team, %{name: "Drew Patel"})
      sam = member_fixture(team, %{name: "Sam Rivera", email: nil})
      wren = member_fixture(team, %{name: "Wren Adams"})
      jordan = member_fixture(team, %{name: "Jordan Lee"})

      rows = %{
        drew: attendance_fixture(activity, drew, %{status: "attending"}),
        sam: attendance_fixture(activity, sam, %{status: "attending"}),
        wren: attendance_fixture(activity, wren, %{status: "requested"}),
        jordan: attendance_fixture(activity, jordan, %{status: "attending"}),
        jordan_2: attendance_fixture(activity, jordan, %{status: "absent"})
      }

      %{
        user: user,
        team: team,
        activity: activity,
        drew: drew,
        sam: sam,
        wren: wren,
        jordan: jordan,
        rows: rows,
        now: now
      }
    end

    defp checked(ctx, names), do: for({name, status} <- names, do: {ctx[name].id, status})

    test "removes from D4H and the copy, and emails only a signed up member with an email", ctx do
      ctx.rows |> Map.values() |> AttendanceStub.stub()
      checked = checked(ctx, drew: "attending", sam: "attending", wren: "requested")

      assert {:ok, result} =
               RemoveMembers.call(ctx.team, ctx.activity, checked, " Sorry ", ctx.user, ctx.now)

      assert Enum.map(result.removed, & &1.name) == ["Drew Patel", "Sam Rivera", "Wren Adams"]
      assert Enum.map(result.emailed, & &1.name) == ["Drew Patel"]
      assert result.not_removed == []

      for name <- [:drew, :sam, :wren] do
        id = ctx.rows[name].d4h_attendance_id
        assert_received {:d4h_write, :delete, ^id}
      end

      assert Attendance |> Repo.all() |> Enum.map(& &1.member_id) |> Enum.uniq() == [
               ctx.jordan.id
             ]

      # Its job runs inline in tests.
      assert [%ActivityUpdate{kind: :removal, status: :sent, message: "Sorry"} = update] =
               Repo.all(ActivityUpdate)

      assert update.member_id == ctx.drew.id
      assert_received {:email, %{to: [{"Drew Patel", _}], subject: subject, text_body: text}}
      assert subject == "You're no longer on #{ctx.activity.title}"
      assert text =~ "Sorry"
      assert text =~ "You're no longer on this activity."
      refute text =~ "Open activity"
      refute_received {:email, _}
      assert [%ChangeSet{source: :remove}] = Repo.all(ChangeSet)

      reasons = ChangeSetRow |> Repo.all() |> Map.new(&{&1.member_id, &1.reason})
      assert reasons == %{ctx.drew.id => "Sorry", ctx.sam.id => nil, ctx.wren.id => nil}
    end

    test "email: false removes a signed up member with no email, keeping the reason", ctx do
      ctx.rows |> Map.values() |> AttendanceStub.stub()

      assert {:ok, %{removed: [_drew], emailed: []}} =
               RemoveMembers.call(
                 ctx.team,
                 ctx.activity,
                 checked(ctx, drew: "attending"),
                 "Told them on the phone",
                 ctx.user,
                 ctx.now,
                 email: false
               )

      assert Repo.all(ActivityUpdate) == []
      refute_received {:email, _}
      assert [%ChangeSetRow{reason: "Told them on the phone"}] = Repo.all(ChangeSetRow)
    end

    test "a member with a row D4H changed stays on, gets no email, and is named (H3)", ctx do
      # D4H has Jordan's second row as signed up now.
      changed = %{ctx.rows.jordan_2 | status: "attending"}
      AttendanceStub.stub([ctx.rows.jordan, changed])

      assert {:ok, result} =
               RemoveMembers.call(
                 ctx.team,
                 ctx.activity,
                 checked(ctx, jordan: "attending"),
                 "Sorry",
                 ctx.user,
                 ctx.now
               )

      assert result.removed == []
      assert [{%Member{name: "Jordan Lee"}, :changed}] = result.not_removed
      assert Repo.all(ActivityUpdate) == []

      # The row D4H deleted leaves the copy; the other stays.
      assert [%Attendance{status: "absent"}] =
               Repo.all_by(Attendance, member_id: ctx.jordan.id)
    end

    test "a refused delete keeps the member on", ctx do
      ctx.rows |> Map.values() |> AttendanceStub.stub(refuse: [ctx.wren.d4h_member_id])

      assert {:ok, %{removed: [], not_removed: [{wren, error}]}} =
               RemoveMembers.call(
                 ctx.team,
                 ctx.activity,
                 checked(ctx, wren: "requested"),
                 nil,
                 ctx.user,
                 ctx.now
               )

      assert wren.id == ctx.wren.id
      assert error =~ "did not answer"
      assert Repo.get_by(Attendance, member_id: ctx.wren.id)
    end

    test "refuses no message, nobody checked, and an activity that can't change", ctx do
      later = DateTime.add(ctx.activity.started_at, 1, :minute)
      drew = checked(ctx, drew: "attending")
      call = &RemoveMembers.call(ctx.team, &1, &2, &3, ctx.user, &4)

      assert {:error, :no_message} = call.(ctx.activity, drew, " ", ctx.now)
      assert {:error, :none_selected} = call.(ctx.activity, [], "Sorry", ctx.now)
      assert {:error, :started} = call.(ctx.activity, drew, "Sorry", later)

      assert {:error, :deleted} =
               call.(%{ctx.activity | deleted_at: ctx.now}, drew, "Sorry", ctx.now)

      assert {:error, :published} =
               call.(%{ctx.activity | is_published: true}, drew, "Sorry", ctx.now)

      assert Repo.all(ChangeSet) == []
    end

    test "a member of another team is never removed", ctx do
      other = member_fixture(team_fixture())

      assert {:ok, %{removed: [], not_removed: []}} =
               RemoveMembers.call(
                 ctx.team,
                 ctx.activity,
                 [{other.id, "attending"}],
                 nil,
                 ctx.user,
                 ctx.now
               )
    end
  end
end
