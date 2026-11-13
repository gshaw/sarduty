defmodule App.DemoCast do
  @moduledoc """
  Try a demo's cast (#857): Coast Range SAR (App.CoastRange) as the JSON SAR Duty
  Records loads into a new demo team (`D4H.create_demo_team/1`), with the visitor as a
  second Owner beside Alex Chen. silver_basin/2 is the demo's second team, Silver Basin
  SAR (App.SilverBasin), in the same shape (#963).

  Pure. cast/2 is what Records keeps, in D4H's shape: members, tags, custom fields,
  groups, qualifications and awards, activities and attendance, equipment with its costs
  and its use, whiteboard notes, and saved places. Each row's key is its Coast Range kind
  and key, like `member:Alex Chen` or `activity:9200003`, and Records answers each key's
  new id. local_rows/2 is what only SAR Duty keeps (endorsements, group rules, ID cards,
  away periods, chores, templates, and travel), for App.Operation.BuildDemoTeam to add
  once the sync has copied the rest.

  Custom fields (#1003): Coast Range's cast makes the demo's organization, WESARA, which
  owns the 27 incident fields, and Silver Basin's joins it. A record's values go by key
  (`fields`), but values for WESARA's fields on Silver Basin go by the ids Records
  answered Coast Range's cast (`customFieldValues`), since its cast never made them.
  """

  alias App.Adapter.D4H.Parse
  alias App.CoastRange
  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.SilverBasin

  @records_kinds [
    :tag,
    :custom_field,
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

  @targets %{
    "event" => "Event",
    "exercise" => "Exercise",
    "incident" => "Incident",
    "member" => "Member",
    "equipment" => "Equipment"
  }

  # Every Records team has these (Records' create_team), under these keys.
  @hours_tags ["Primary Hours", "Secondary Hours"]

  @doc "Records' row key for a Coast Range `{kind, key}`."
  def key({kind, key}), do: "#{kind}:#{key}"

  @doc """
  The cast for a visitor `%{name:, email:}` as of `now`: `%{"team" => …, "rows" => […]}`.
  It makes WESARA, with its fields.
  """
  def cast(%DateTime{} = now, %{name: _name, email: _email} = visitor),
    do: now |> CoastRange.build(visitor: visitor) |> records_cast(:new)

  @doc """
  Silver Basin SAR as of `now`, in cast/2's shape: a demo's second team. It joins the
  organization Coast Range's cast made, `%{id:, ids:}` from Records' answer to it.
  Raises KeyError when the answer lacks a field or option Silver Basin has a value for.
  """
  def silver_basin(%DateTime{} = now, %{id: _id, ids: %{}} = organization),
    do: now |> SilverBasin.build() |> records_cast(organization)

  @doc """
  A template's (or any local row's) `custom_values`, keyed by Coast Range's field and
  option ids, re-keyed by the ids Records answered for them.
  """
  def local_values(values, ids) when is_map(values) do
    Map.new(values, fn {field_id, value} ->
      {ids |> Map.fetch!(key({:custom_field, field_id})) |> Integer.to_string(),
       local_value(value, ids)}
    end)
  end

  defp local_value(option_ids, ids) when is_list(option_ids),
    do: Enum.map(option_ids, &Map.fetch!(ids, key({:custom_field_option, &1})))

  defp local_value(text, _ids), do: text

  defp records_cast(rows, organization) do
    {:team, _key, team, []} = hd(rows)
    fields = for {:custom_field, id, field, []} <- rows, into: %{}, do: {"#{id}", field}
    context = %{fields: fields, organization: organization}
    records = Enum.filter(rows, &records?(&1, organization))
    items = for {:equipment_item, _key, item, _links} <- records, do: item

    %{
      "team" => team_json(team, organization),
      "rows" =>
        Enum.concat([
          equipment_places(items),
          Enum.flat_map(records, &(&1 |> rows() |> put_values(&1, context)))
        ])
    }
  end

  # What Records keeps: a field only when this cast makes it.
  defp records?({:custom_field, _key, field, _links}, organization), do: own?(field, organization)
  defp records?({kind, _key, _row, _links}, _organization), do: kind in @records_kinds

  defp team_json(team, organization) do
    Map.merge(
      %{
        "title" => team.name,
        "timezone" => team.timezone,
        "lat" => team.lat,
        "lng" => team.lng,
        "logo" => "sample"
      },
      organization_json(organization)
    )
  end

  defp organization_json(:new),
    do: %{"organization" => %{"title" => CoastRange.organization().short_name}}

  defp organization_json(%{id: id}), do: %{"organizationId" => id}

  # A field this cast makes: every field of the cast that makes the organization, and only
  # the team's own for one that joins it.
  defp own?(field, :new), do: field != nil
  defp own?(field, _joined), do: not CustomField.organisation?(field)

  # A record's custom field values: by key for the fields this cast makes, and by
  # Records' ids for its organization's when it joins one.
  defp put_values([row], {_kind, _key, %{custom_values: %{} = values}, _links}, context)
       when map_size(values) > 0 do
    {by_key, by_id} =
      values
      |> Enum.sort()
      |> Enum.split_with(fn {id, _value} -> own?(context.fields[id], context.organization) end)

    row = if by_key == [], do: row, else: Map.put(row, "fields", Map.new(by_key, &field_value/1))

    if by_id == [],
      do: [row],
      else: [
        put_in(
          row,
          ["body", "customFieldValues"],
          Enum.map(by_id, &id_value(&1, context.organization.ids))
        )
      ]
  end

  defp put_values(rows, _record, _context), do: rows

  defp field_value({id, value}), do: {key({:custom_field, id}), option_keys(value)}

  defp option_keys(option_ids) when is_list(option_ids),
    do: Enum.map(option_ids, &key({:custom_field_option, &1}))

  defp option_keys(text), do: text

  defp id_value({id, value}, ids),
    do: %{"id" => Map.fetch!(ids, key({:custom_field, id})), "value" => local_value(value, ids)}

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

  # D4H's POST body (#1003). D4H's default is RESTRICTED, so it is always sent. Each
  # option gets a key, so a value names it.
  defp rows({:custom_field, id, %CustomField{} = field, []}) do
    options = Enum.sort_by(field.options, & &1["ordering"])

    {body, option_keys} =
      if CustomField.choice?(field) do
        labels = Enum.map(options, &Map.take(&1, ~w(label ordering)))
        keys = Enum.map(options, &key({:custom_field_option, &1["id"]}))
        {field |> field_body() |> Map.put("options", labels), keys}
      else
        {field_body(field), []}
      end

    row =
      "custom-fields"
      |> row({:custom_field, id}, body)
      |> Map.put("optionKeys", option_keys)

    [if(CustomField.organisation?(field), do: Map.put(row, "owner", "organization"), else: row)]
  end

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
        "startsAt" => Parse.day_text(member.joined_at),
        "endsAt" => Parse.day_text(member.left_at),
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
    body = %{
      "startsAt" => Parse.day_text(award.starts_at),
      "endsAt" => Parse.day_text(award.ends_at)
    }

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

    body = Map.merge(body, costs(item))

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

  defp field_body(field) do
    %{
      "targetResourceType" => Map.fetch!(@targets, field.target),
      "title" => field.title,
      "type" => String.upcase(field.field_type),
      "mandatory" => field.required,
      "restricted" => if(field.restricted, do: "RESTRICTED", else: "UNRESTRICTED"),
      "memberPrivacy" => String.upcase(field.member_privacy || "hidden"),
      "ordering" => field.ordering,
      "hint" => field.hint,
      "valueUnits" => field.value_units
    }
    |> Map.reject(fn {_field, value} -> is_nil(value) end)
  end

  # D4H's costs, whole cents (Records' R2). Blank ones are left out.
  defp costs(item) do
    %{
      "costPerDistance" => item.cost_per_km_cents,
      "costPerHour" => item.cost_per_hour_cents,
      "costPerUse" => item.cost_per_use_cents
    }
    |> Map.reject(fn {_field, value} -> is_nil(value) end)
  end

  # Each kind and each place the items name, before the items. A kind costs what every
  # item of it costs, when they all cost the same.
  defp equipment_places(items) do
    kinds = items |> Enum.group_by(& &1.kind) |> Enum.sort() |> Enum.map(&kind_row/1)

    places =
      for title <- items |> Enum.map(& &1.location_title) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
          do: row("equipment-locations", {:equipment_location, title}, %{"title" => title})

    kinds ++ places
  end

  defp kind_row({kind, [item | _rest] = same}) do
    shared = if same |> Enum.map(&costs/1) |> Enum.uniq() |> length() == 1, do: costs(item)
    body = %{"title" => kind, "type" => String.upcase(item.item_type)}
    row("equipment-kinds", {:equipment_kind, kind}, Map.merge(body, shared || %{}))
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
