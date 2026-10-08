defmodule App.Operation.SeedHostedTeam do
  @moduledoc """
  Made-up members, activities, attendance, qualifications, and groups for a new hosted
  team, so a team trying SAR Duty sees every page with something on it. Never real
  people: the names are invented and the emails are at example.com.
  """

  alias App.Hosted
  alias App.Model.Activity

  @members [
    {"Avery Morrison", "Team Leader"},
    {"Blair MacDonald", "Searcher"},
    {"Casey Fraser", "Searcher"},
    {"Devon Campbell", "Navigator"},
    {"Emery Stewart", "First Aid"},
    {"Finley Murray", "Searcher"},
    {"Harper Doucette", "Radio Operator"},
    {"Jordan LeBlanc", "Searcher"},
    {"Kendall Burke", "Searcher"},
    {"Morgan MacNeil", "Training Officer"}
  ]

  @qualifications [
    {"Ground Search and Rescue", nil},
    {"Standard First Aid", 36},
    {"Search Manager", 60}
  ]

  @activities [
    {"exercise", "Night navigation", 7, 3, ["Primary Hours", "Training"]},
    {"event", "Monthly meeting", 14, 2, ["Secondary Hours"]},
    {"incident", "Missing hiker", 20, 6, ["Primary Hours"]},
    {"exercise", "Rope rescue practice", 28, 4, ["Primary Hours", "Training"]},
    {"event", "Community fair booth", 35, 5, ["Secondary Hours"]},
    {"exercise", "Mock search", 49, 6, ["Primary Hours", "Training"]},
    {"event", "Monthly meeting", 44, 2, ["Secondary Hours"]},
    {"incident", "Overdue kayaker", 60, 4, ["Primary Hours"]}
  ]

  def call(%Hosted.Team{} = team, now) do
    today = DateTime.truncate(now, :second)
    members = Enum.with_index(@members, &create_member(team, &1, &2, today))
    tags = create_tags(team)

    @activities
    |> Enum.with_index()
    |> Enum.each(&create_activity(team, &1, members, tags, today))

    create_qualifications(team, members, today)
    create_groups(team, members)
    :ok
  end

  defp create_member(team, {name, position}, index, today) do
    email = name |> String.downcase() |> String.replace(" ", ".")

    {:ok, member} =
      Hosted.create(team, "members", %{
        name: name,
        position: position,
        ref: "#{101 + index}",
        email: "#{email}@example.com",
        phone: "902-555-01#{String.pad_leading("#{index}", 2, "0")}",
        status: "OPERATIONAL",
        permission: 2,
        starts_at: DateTime.add(today, -(400 + index * 90), :day)
      })

    member
  end

  defp create_tags(team) do
    for title <- [Activity.primary_hours_tag(), Activity.secondary_hours_tag(), "Training"],
        into: %{} do
      {:ok, tag} = Hosted.create(team, "tags", %{title: title})
      {title, tag.id}
    end
  end

  defp create_activity(
         team,
         {{kind, title, days_ago, hours, tags}, index},
         members,
         tag_ids,
         today
       ) do
    starts_at = today |> DateTime.add(-days_ago, :day) |> at_hour(18)
    ends_at = DateTime.add(starts_at, hours, :hour)

    {:ok, activity} =
      Hosted.create(team, "#{kind}s", %{
        title: title,
        town: "Truro",
        region: "Nova Scotia",
        country: "Canada",
        starts_at: starts_at,
        ends_at: ends_at
      })

    {:ok, _activity} =
      Hosted.update(team, "#{kind}s", activity.id, %{
        tag_ids: Enum.map(tags, &tag_ids[&1]),
        published: true
      })

    # Every member but a few, a different few each time.
    for {member, member_index} <- Enum.with_index(members), rem(member_index + index, 4) != 0 do
      {:ok, _attendance} =
        Hosted.create(team, "attendance", %{
          activity_id: activity.id,
          member_id: member.id,
          status: "ATTENDING",
          starts_at: starts_at,
          ends_at: ends_at
        })
    end
  end

  defp create_qualifications(team, members, today) do
    for {{title, months}, index} <- Enum.with_index(@qualifications) do
      {:ok, qualification} =
        Hosted.create(team, "member-qualifications", %{
          title: title,
          expires_months_default: months
        })

      for {member, member_index} <- Enum.with_index(members), rem(member_index, index + 1) == 0 do
        award(
          team,
          qualification,
          member,
          today |> DateTime.add(-(100 + member_index * 30), :day)
        )
      end
    end
  end

  defp award(team, qualification, member, starts_at) do
    months = qualification.expires_months_default

    {:ok, _award} =
      Hosted.create(team, "member-qualification-awards", %{
        member_id: member.id,
        qualification_id: qualification.id,
        starts_at: starts_at,
        ends_at: months && DateTime.add(starts_at, months * 30, :day)
      })
  end

  defp create_groups(team, members) do
    for {title, every} <- [{"Ground Search", 1}, {"Search Managers", 3}] do
      {:ok, group} = Hosted.create(team, "member-groups", %{title: title})

      for {member, index} <- Enum.with_index(members), rem(index, every) == 0 do
        {:ok, _membership} =
          Hosted.create(team, "member-group-memberships", %{
            group_id: group.id,
            member_id: member.id
          })
      end
    end
  end

  defp at_hour(datetime, hour), do: %{datetime | hour: hour, minute: 0, second: 0}
end
