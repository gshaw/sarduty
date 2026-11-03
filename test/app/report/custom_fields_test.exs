defmodule App.Report.CustomFieldsTest do
  # A team's D4H custom fields in reports, by their titles in backticks (#840).
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.EquipmentItem
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Context
  alias App.Report.Error

  @now ~U[2026-06-15 19:00:00Z]

  defp run!(text, team) do
    case Report.run(text, team, %{}, @now) do
      {:ok, result} -> result.rows
      {:error, error} -> flunk("#{text}\n#{Error.text(error)}")
    end
  end

  defp error(text, team),
    do: text |> Report.check(team, %{}, @now) |> then(fn {:error, e} -> Error.text(e) end)

  defp incident(team, values, attrs \\ %{}) do
    activity_fixture(
      team,
      Map.merge(
        %{activity_kind: "incident", started_at: ~U[2026-03-01 18:00:00Z], custom_values: values},
        attrs
      )
    )
  end

  defp choice(id, labels),
    do: for({label, i} <- Enum.with_index(labels), do: %{"id" => id + i, "label" => label})

  setup do
    team = team_fixture()

    task =
      custom_field_fixture(team, %{
        title: "Task Type",
        field_type: "single_choice",
        options: choice(100, ["Search", "Rescue"])
      })

    helped = custom_field_fixture(team, %{title: "People helped", field_type: "number"})
    %{team: team, task: task, helped: helped}
  end

  defp id(field), do: Integer.to_string(field.d4h_custom_field_id)

  test "a choice field groups and compares by its options' labels, in any case", ctx do
    incident(ctx.team, %{id(ctx.task) => [100]})
    incident(ctx.team, %{id(ctx.task) => [100]})
    incident(ctx.team, %{id(ctx.task) => [101]})
    incident(ctx.team, %{})

    rows =
      run!(
        "select `task type`, count(id) from activities group by `Task Type` order by count(id) desc",
        ctx.team
      )

    assert rows == [["Search", 2], ["Rescue", 1], [nil, 1]]
    assert [[1]] = run!("select count(id) from activities where `Task Type` = 'Rescue'", ctx.team)
  end

  test "a number field reads the number in D4H's text, and blank when it holds none", ctx do
    incident(ctx.team, %{id(ctx.helped) => "3"})
    incident(ctx.team, %{id(ctx.helped) => " 2 "})
    incident(ctx.team, %{id(ctx.helped) => "N/A"})

    assert [[5, 2]] =
             run!("select sum(`People helped`), count(`People helped`) from activities", ctx.team)
  end

  test "a multiple choice field is a list of labels, as tags are", %{team: team} do
    areas =
      custom_field_fixture(team, %{
        target: "equipment",
        title: "Kit",
        field_type: "multiple_choice",
        options: choice(200, ["Rope", "Water", "Medical"])
      })

    equipment_item_fixture(team, %{title: "Bag 1", custom_values: %{id(areas) => [200, 202]}})
    equipment_item_fixture(team, %{title: "Bag 2", custom_values: %{id(areas) => [201]}})
    equipment_item_fixture(team, %{title: "Bag 3", custom_values: %{id(areas) => []}})

    titles = fn where ->
      for [id] <- run!("select title from equipment where #{where}", team),
          do: App.Repo.get!(EquipmentItem, id).title
    end

    assert titles.("`Kit` includes ('Medical')") == ["Bag 1"]
    assert "`Kit` excludes ('Rope')" |> titles.() |> Enum.sort() == ["Bag 2", "Bag 3"]
    assert titles.("`Kit` is null") == ["Bag 3"]
  end

  # Toronto keeps its clocks changing, so the day's offset comes from the date itself.
  test "a date field is the day it says in the team's zone, never the day before" do
    team = team_fixture(%{timezone: "America/Toronto"})
    done = custom_field_fixture(team, %{title: "Report done", field_type: "date"})
    incident(team, %{id(done) => "2026-01-01"})
    incident(team, %{id(done) => "2026-07-01"})

    assert [[2026, 1], [2026, 7]] =
             run!(
               "select year(`Report done`), month(`Report done`) from activities order by `Report done`",
               team
             )

    assert [[1]] =
             run!(
               "select count(id) from activities where `Report done` = date '2026-01-01'",
               team
             )
  end

  test "a date and time field is a moment", %{team: team} do
    paged = custom_field_fixture(team, %{title: "Paged at", field_type: "datetime"})
    incident(team, %{id(paged) => "2026-01-01T06:30:00.000Z"})

    # 06:30 UTC is still Dec 31 in Vancouver.
    assert [[2025]] = run!("select year(`Paged at`) from activities", team)
  end

  test "one title on two kinds is one field, read from each activity's own", %{team: team} do
    exercise = custom_field_fixture(team, %{target: "exercise", title: "Event leader"})
    event = custom_field_fixture(team, %{target: "event", title: "Event leader"})
    activity_fixture(team, %{activity_kind: "exercise", custom_values: %{id(exercise) => "Ana"}})
    activity_fixture(team, %{activity_kind: "event", custom_values: %{id(event) => "Bo"}})

    assert [["Ana"], ["Bo"]] =
             run!("select `Event leader` from activities order by `Event leader`", team)
  end

  test "one title on two kinds with different types reads as text", %{team: team} do
    exercise =
      custom_field_fixture(team, %{
        target: "exercise",
        title: "Lead",
        field_type: "single_choice",
        options: choice(300, ["Ana"])
      })

    event = custom_field_fixture(team, %{target: "event", title: "Lead"})
    activity_fixture(team, %{activity_kind: "exercise", custom_values: %{id(exercise) => [300]}})
    activity_fixture(team, %{activity_kind: "event", custom_values: %{id(event) => "Bo"}})

    assert [["Ana"], ["Bo"]] = run!("select `Lead` from activities order by `Lead`", team)
  end

  test "two fields with one title on one kind can't be told apart", %{team: team} do
    custom_field_fixture(team, %{title: "Notes"})
    custom_field_fixture(team, %{title: "Notes"})

    assert error("select `Notes` from activities", team) =~
             "Two of activities' fields are called `Notes`. Rename one to report on it."
  end

  test "a parent's custom field takes a dot", ctx do
    member = member_fixture(ctx.team)
    rescued = incident(ctx.team, %{id(ctx.task) => [101]})
    attendance_fixture(rescued, member, %{duration_in_minutes: 120})

    assert [["Rescue", 1]] =
             run!(
               "select activity.`Task Type`, count(id) from attendance group by activity.`Task Type`",
               ctx.team
             )
  end

  test "a typo gets the closest title, and an archived field is no field", ctx do
    custom_field_fixture(ctx.team, %{title: "Old cause", archived_at: ~U[2026-01-01 00:00:00Z]})

    assert error("select `Task Typ` from activities", ctx.team) =~ "Did you mean `Task Type`?"
    assert error("select `Old cause` from activities", ctx.team) =~ "no field `Old cause`"
  end

  test "a member field is one the team copies, and never a restricted one", %{team: team} do
    copied =
      custom_field_fixture(team, %{target: "member", title: "Call sign", copy_values: true})

    custom_field_fixture(team, %{target: "member", title: "Allergies"})

    custom_field_fixture(team, %{
      target: "member",
      title: "Gender",
      restricted: true,
      copy_values: true
    })

    member_fixture(team, %{name: "Ana", custom_values: %{id(copied) => "CR 7"}})

    assert [[_ana, "CR 7"]] = run!("select name, `Call sign` from members", team)

    assert error("select `Allergies` from members", team) =~
             "The team does not copy `Allergies`. Pick it on team settings' Members tab."

    assert error("select `Gender` from members", team) =~
             "SAR Duty never copies `Gender`: it is restricted."
  end

  test "a member reads an activity's fields, but no restricted one, member, or item", ctx do
    custom_field_fixture(ctx.team, %{title: "Debrief", restricted: true})
    custom_field_fixture(ctx.team, %{target: "member", title: "Call sign", copy_values: true})
    custom_field_fixture(ctx.team, %{target: "equipment", title: "Serviced"})
    member = Context.new(ctx.team, @now, team_admin?: false)
    admin = Context.new(ctx.team, @now)

    shown = fn context, name ->
      subject = Catalog.subject(name)

      subject
      |> Catalog.custom_fields(context)
      |> Enum.filter(&Catalog.field(subject, &1.name, context))
      |> Enum.map(& &1.name)
    end

    assert shown.(member, "activities") == ["`People helped`", "`Task Type`"]
    assert shown.(admin, "activities") == ["`Debrief`", "`People helped`", "`Task Type`"]
    assert shown.(member, "members") == []
    assert shown.(admin, "members") == ["`Call sign`"]
    assert shown.(member, "equipment") == []
    assert shown.(admin, "equipment") == ["`Serviced`"]
  end

  test "a team on Records has no custom fields" do
    %{team: team} = records_team_with_user_fixture()
    custom_field_fixture(team, %{title: "Task Type"})

    assert error("select `Task Type` from activities", team) =~ "no field `Task Type`"
  end

  test "a backtick is closed and holds a title", %{team: team} do
    assert error("select `Task Type from activities", team) =~ "Close the backtick"
    assert error("select `` from activities", team) =~ "Write a field's title"
  end
end
