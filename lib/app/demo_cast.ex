defmodule App.DemoCast do
  @moduledoc """
  Try a demo's cast (#857): Coast Range SAR (App.CoastRange) as the JSON SAR Duty
  Records loads into a new demo team (`D4H.create_demo_team/1`), with the visitor as a
  second Owner beside Alex Chen. silver_basin/1 is the demo's second team, Silver Basin
  SAR (App.SilverBasin), in the same shape (#963).

  Pure. cast/2 is what Records keeps, in D4H's shape: members, tags, groups,
  qualifications and awards, activities and attendance, equipment and its use, whiteboard
  notes, and saved places. Each row's key is its Coast Range kind and key, like
  `member:Alex Chen` or `activity:9200003`, and Records answers each key's new id.
  local_rows/2 is what only SAR Duty keeps (endorsements, group rules, ID cards, away
  periods, chores, templates, and travel), for App.Operation.BuildDemoTeam to add once
  the sync has copied the rest.

  Custom fields stay out: Records has none (`D4H.custom_fields?/1`).
  """

  alias App.CoastRange
  alias App.Model.Activity
  alias App.SilverBasin

  @records_kinds [
    :tag,
    :member,
    :group,
    :group_member,
    :qualification,
    :award,
    :activity,
    :attendance,
    :equipment_item,
    :equipment_usage,
    :whiteboard_note,
    :location_bookmark
  ]
  @local_kinds [
    :endorsement,
    :endorsement_qualification,
    :group_rule,
    :group_rule_reference,
    :member_card,
    :away_period,
    :chore_category,
    :chore_category_tag,
    :chore_event,
    :chore,
    :template,
    :template_tag,
    :template_group,
    :template_item,
    :home_coordinate,
    :route_distance,
    :trip
  ]

  # Every Records team has these (Records' create_team), under these keys.
  @hours_tags ["Primary Hours", "Secondary Hours"]

  @doc "Records' row key for a Coast Range `{kind, key}`."
  def key({kind, key}), do: "#{kind}:#{key}"

  @doc """
  The cast for a visitor `%{name:, email:}` as of `now`: `%{"team" => …, "rows" => […]}`.
  """
  def cast(%DateTime{} = now, %{name: _name, email: _email} = visitor),
    do: now |> CoastRange.build(visitor: visitor) |> records_cast()

  @doc "Silver Basin SAR as of `now`, in cast/2's shape: a demo's second team."
  def silver_basin(%DateTime{} = now), do: now |> SilverBasin.build() |> records_cast()

  defp records_cast(rows) do
    {:team, _key, team, []} = hd(rows)
    records = for {kind, _key, _row, _links} = row <- rows, kind in @records_kinds, do: row
    items = for {:equipment_item, _key, item, _links} <- records, do: item

    %{
      "team" => %{
        "title" => team.name,
        "timezone" => team.timezone,
        "lat" => team.lat,
        "lng" => team.lng,
        "logo" => "sample"
      },
      "rows" =>
        Enum.concat([
          equipment_places(items),
          Enum.flat_map(records, &rows/1)
        ])
    }
  end

  @doc """
  What only SAR Duty keeps for the visitor `%{name:, email:}`, as App.CoastRange.build/2
  gives it: `{kind, key, struct, links}`, in the order they insert.
  """
  def local_rows(%DateTime{} = now, visitor) do
    for {kind, _key, _row, _links} = row <- CoastRange.build(now, visitor: visitor),
        kind in @local_kinds,
        do: row
  end

  defp rows({:tag, title, _tag, []}) when title in @hours_tags, do: []

  defp rows({:tag, title, _tag, []}),
    do: [row("tags", {:tag, title}, %{"title" => title})]

  defp rows({:member, name, member, []}) do
    body =
      %{
        "name" => member.name,
        "ref" => member.ref_id,
        "position" => member.position,
        "email" => member.email,
        "phone" => %{"mobile" => member.phone},
        "deprecatedAddress" => member.address,
        "status" => member.d4h_status,
        "startsAt" => iso(member.joined_at),
        "endsAt" => iso(member.left_at),
        "permission" => member.d4h_permission
      }
      |> Map.reject(fn {_field, value} -> is_nil(value) end)

    # The visitor joins as an Owner, as a real team admin is one, and logs in by their
    # email. No sample photo: it would be a stranger's face on their own card.
    row = row("members", {:member, name}, body)
    [if(member.not_a_person or name == :visitor, do: row, else: Map.put(row, "photo", "sample"))]
  end

  defp rows({:group, id, group, []}),
    do: [row("member-groups", {:group, id}, %{"title" => group.title})]

  defp rows({:group_member, _key, _row, links}),
    do: [
      ref_row("member-group-memberships", %{},
        groupId: links[:group_id],
        memberId: links[:member_id]
      )
    ]

  defp rows({:qualification, id, qualification, []}) do
    body = %{
      "title" => qualification.title,
      "expiresMonthsDefault" => qualification.expires_months_default
    }

    [row("member-qualifications", {:qualification, id}, body)]
  end

  defp rows({:award, _key, award, links}) do
    body = %{"startsAt" => iso(award.starts_at), "endsAt" => iso(award.ends_at)}

    [
      ref_row("member-qualification-awards", body,
        memberId: links[:member_id],
        qualificationId: links[:qualification_id]
      )
    ]
  end

  defp rows({:activity, id, %Activity{} = activity, []}) do
    body =
      %{
        "reference" => activity.ref_id,
        "referenceDescription" => activity.title,
        "description" => activity.description,
        "trackingNumber" => activity.tracking_number,
        "startsAt" => iso(activity.started_at),
        "endsAt" => iso(activity.finished_at),
        "address" => %{
          "street" => activity.address || "",
          "town" => "",
          "region" => "",
          "country" => ""
        },
        "location" => location(activity.coordinate)
      }
      |> Map.reject(fn {_field, value} -> is_nil(value) end)

    row =
      "#{activity.activity_kind}s"
      |> row({:activity, id}, body)
      |> Map.put("tags", Enum.map(activity.tags, &key({:tag, &1})))

    [if(activity.is_published, do: Map.put(row, "published", true), else: row)]
  end

  defp rows({:attendance, _key, attendance, links}) do
    body = %{
      "status" => String.upcase(attendance.status),
      "startsAt" => iso(attendance.started_at),
      "endsAt" => iso(attendance.finished_at)
    }

    # Keyed, so a trip can name the row by Records' id.
    row =
      ref_row("attendance", body, memberId: links[:member_id], activityId: links[:activity_id])

    [Map.put(row, "key", key({:attendance, attendance.d4h_attendance_id}))]
  end

  defp rows({:equipment_item, id, item, links}) do
    body = %{
      "ref" => item.title,
      "type" => String.upcase(item.item_type),
      "status" => String.upcase(item.status),
      "barcode" => item.barcode,
      "serial" => item.serial,
      "dateExpires" => iso(item.expires_at)
    }

    {resource_type, place} =
      if links[:member_id],
        do: {"Member", links[:member_id]},
        else: {"EquipmentLocation", {:equipment_location, item.location_title}}

    row =
      row(
        "equipment",
        {:equipment_item, id},
        Map.put(body, "location", %{"resourceType" => resource_type})
      )

    [
      Map.put(row, "refs", %{
        "kindId" => key({:equipment_kind, item.kind}),
        "location.id" => key(place)
      })
    ]
  end

  # D4H's distance is meters (App.Adapter.D4H.EquipmentUsage).
  defp rows({:equipment_usage, _key, usage, links}) do
    body =
      %{
        "duration" => usage.minutes,
        "distance" => usage.distance && usage.distance * 1000,
        "used" => usage.used
      }
      |> Map.reject(fn {_field, value} -> is_nil(value) end)

    [
      ref_row("equipment-usages", body,
        activityId: links[:activity_id],
        equipmentId: links[:equipment_item_id]
      )
    ]
  end

  defp rows({:whiteboard_note, id, note, []}) do
    body = %{
      "text" => note.text,
      "url" => note.url,
      "important" => note.important,
      "archivedAt" => iso(note.archived_at)
    }

    [row("whiteboard", {:whiteboard_note, id}, Map.reject(body, fn {_k, v} -> is_nil(v) end))]
  end

  defp rows({:location_bookmark, title, bookmark, []}) do
    body = %{"title" => bookmark.title, "location" => location(bookmark.coordinate)}

    body =
      if bookmark.address,
        do: Map.put(body, "address", %{"street" => bookmark.address}),
        else: body

    [row("location-bookmarks", {:location_bookmark, title}, body)]
  end

  # Each kind and each place the items name, before the items.
  defp equipment_places(items) do
    kinds =
      for item <- Enum.uniq_by(items, & &1.kind),
          do:
            row("equipment-kinds", {:equipment_kind, item.kind}, %{
              "title" => item.kind,
              "type" => String.upcase(item.item_type)
            })

    places =
      for title <- items |> Enum.map(& &1.location_title) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
          do: row("equipment-locations", {:equipment_location, title}, %{"title" => title})

    kinds ++ places
  end

  defp row(resource, ref, body), do: %{"resource" => resource, "key" => key(ref), "body" => body}

  defp ref_row(resource, body, refs) do
    %{
      "resource" => resource,
      "body" => body,
      "refs" => Map.new(refs, fn {field, ref} -> {Atom.to_string(field), key(ref)} end)
    }
  end

  defp location(nil), do: nil

  defp location(coordinate) do
    [lat, lng] = coordinate |> String.split(",") |> Enum.map(&String.to_float/1)
    %{"latitude" => lat, "longitude" => lng}
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = time), do: DateTime.to_iso8601(time)
end
