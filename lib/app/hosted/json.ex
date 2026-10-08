defmodule App.Hosted.JSON do
  @moduledoc """
  Hosted rows in D4H's v3 JSON shape: the fields the D4H adapter reads, named and nested
  as D4H names them. A field the adapter doesn't read is left out.
  """

  alias App.Hosted

  @kinds %{"event" => "Event", "exercise" => "Exercise", "incident" => "Incident"}

  def page(rows, total_size, page, size) do
    %{results: Enum.map(rows, &render/1), page: page, pageSize: size, totalSize: total_size}
  end

  def whoami(%Hosted.Team{} = team) do
    # The key belongs to the team, not a person, so its member is "SAR Duty" with id 0,
    # which no member has.
    %{
      members: [
        %{id: 0, resourceType: "Member", name: "SAR Duty", hasAccess: true, owner: team_ref(team)}
      ]
    }
  end

  def error(status, title), do: %{statusCode: status, error: reason(status), title: title}

  def render(%Hosted.Team{} = team) do
    %{
      id: team.id,
      resourceType: "Team",
      title: team.title,
      subdomain: team.subdomain,
      timezone: team.timezone,
      location: point(team.lat, team.lng)
    }
  end

  def render(%Hosted.Member{} = member) do
    %{
      id: member.id,
      resourceType: "Member",
      owner: owner(member),
      name: member.name,
      ref: member.ref,
      position: member.position,
      email: %{value: member.email},
      mobile: %{phone: member.phone},
      deprecatedAddress: member.address,
      permission: member.permission,
      status: member.status,
      startsAt: iso(member.starts_at),
      endsAt: iso(member.ends_at)
    }
    |> timestamps(member)
  end

  def render(%Hosted.Activity{} = activity) do
    %{
      id: activity.id,
      resourceType: Map.fetch!(@kinds, activity.kind),
      owner: owner(activity),
      reference: activity.reference,
      referenceDescription: activity.title,
      description: activity.description,
      trackingNumber: activity.tracking_number,
      published: activity.published,
      address: %{
        street: activity.street,
        town: activity.town,
        region: activity.region,
        country: activity.country
      },
      location: point(activity.lat, activity.lng),
      startsAt: iso(activity.starts_at),
      endsAt: iso(activity.ends_at),
      tags: Enum.map(activity.tag_ids, &%{resourceType: "Tag", id: &1})
    }
    |> timestamps(activity)
  end

  def render(%Hosted.Attendance{} = attendance) do
    %{
      id: attendance.id,
      resourceType: "Attendance",
      owner: owner(attendance),
      activity: %{
        resourceType: Map.fetch!(@kinds, attendance.activity_kind),
        id: attendance.activity_id
      },
      member: %{resourceType: "Member", id: attendance.member_id},
      status: attendance.status,
      startsAt: iso(attendance.starts_at),
      endsAt: iso(attendance.ends_at),
      duration: Hosted.Attendance.duration(attendance)
    }
    |> timestamps(attendance)
  end

  def render(%Hosted.Qualification{} = qualification) do
    %{
      id: qualification.id,
      resourceType: "MemberQualification",
      owner: owner(qualification),
      title: qualification.title,
      description: qualification.description,
      expiresMonthsDefault: qualification.expires_months_default
    }
    |> timestamps(qualification)
  end

  def render(%Hosted.QualificationAward{} = award) do
    %{
      id: award.id,
      resourceType: "MemberQualificationAward",
      owner: owner(award),
      member: %{resourceType: "Member", id: award.member_id},
      qualification: %{resourceType: "MemberQualification", id: award.qualification_id},
      startsAt: iso(award.starts_at),
      endsAt: iso(award.ends_at)
    }
    |> timestamps(award)
  end

  def render(%Hosted.Group{} = group) do
    %{id: group.id, resourceType: "MemberGroup", owner: owner(group), title: group.title}
    |> timestamps(group)
  end

  def render(%Hosted.GroupMembership{} = membership) do
    %{
      id: membership.id,
      resourceType: "MemberGroupMembership",
      owner: owner(membership),
      group: %{resourceType: "MemberGroup", id: membership.group_id},
      member: %{resourceType: "Member", id: membership.member_id}
    }
    |> timestamps(membership)
  end

  def render(%Hosted.Tag{} = tag) do
    %{id: tag.id, resourceType: "Tag", owner: owner(tag), title: tag.title}
    |> timestamps(tag)
  end

  defp owner(%{hosted_team_id: id}), do: %{resourceType: "Team", id: id}

  defp team_ref(%Hosted.Team{} = team),
    do: %{resourceType: "Team", id: team.id, title: team.title}

  defp timestamps(map, row),
    do: Map.merge(map, %{createdAt: iso(row.inserted_at), updatedAt: iso(row.updated_at)})

  defp point(lat, lng) when is_number(lat) and is_number(lng),
    do: %{type: "Point", coordinates: [lng, lat]}

  defp point(_lat, _lng), do: nil

  defp iso(nil), do: nil
  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp reason(400), do: "Bad Request"
  defp reason(401), do: "Unauthorized"
  defp reason(403), do: "Forbidden"
  defp reason(404), do: "Not Found"
  defp reason(_status), do: "Error"
end
