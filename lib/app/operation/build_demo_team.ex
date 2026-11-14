defmodule App.Operation.BuildDemoTeam do
  @moduledoc """
  Builds a visitor's demo the first time they open its link (#857), the way a team signs
  up: Coast Range SAR, Silver Basin SAR beside it, and WESARA's copy with both in it and
  its made-up Task report on (#963, App.Operation.AddDemoForms). Records makes each team from its cast and picks its ids (App.DemoCast). SAR
  Duty then adds each team, marked as the demo's before anything can send, refreshes it
  like any team, and adds what only SAR Duty
  keeps on Coast Range (endorsements, ID cards, away periods, chores, templates with their
  field values), matched through Records' ids. Records makes WESARA with Coast Range's
  cast, owning the incident fields, and SAR Duty keeps its id (#1003). Silver Basin never
  syncs after this: nobody opens its team pages.

  A failure removes whatever was made, in Records too, so the next open starts clean.
  Runs in App.Worker.BuildDemoTeamWorker, and tells the waiting page through topic/1.

  build_dev_teams/2 makes the same three in the dev database (tools/dev-teams.exs).
  """

  import Ecto.Query, only: [where: 2, where: 3]

  alias App.Adapter.D4H
  alias App.CoastRange
  alias App.DemoCast
  alias App.Model.Activity
  alias App.Model.DemoTeam
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Organization
  alias App.Model.OrganizationAdmin
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Model.Template
  alias App.Model.Trip
  alias App.Operation.AddDemoForms
  alias App.Operation.DeleteTeam
  alias App.Operation.RefreshD4HData
  alias App.Repo
  alias App.SilverBasin

  require Logger

  # The team's settings from the cast, as a team that uses each feature has them, and
  # its letters' signer, so letters print as a real team's do.
  @settings [
    :name,
    :legal_name,
    :abbreviated_name,
    :mailing_address,
    :city,
    :postal_code,
    :authorized_by_name,
    :authorized_by_title,
    :authorized_by_phone,
    :authorized_by_email,
    :member_logins,
    :chores_enabled,
    :certificates_enabled,
    :id_cards_enabled,
    :whiteboard_enabled,
    :travel_enabled
  ]

  @doc "The settings a demo copies from Coast Range SAR."
  def settings, do: @settings

  @doc "The topic a demo's build tells, as `{:demo_built, demo_id, result}`."
  def topic(%DemoTeam{id: id}), do: "demo:#{id}"

  @doc "`{:ok, team}`, Coast Range's, or `{:error, reason}` with nothing left behind."
  # Built already, it tells the topic too: a page that subscribed after the build
  # finished is waiting on this job.
  def call(%DemoTeam{team_id: team_id} = demo, _now) when is_integer(team_id),
    do: tell(demo, {:ok, Team.get!(team_id)})

  def call(%DemoTeam{} = demo, now) do
    visitor = visitor(demo)

    result =
      with {:ok, records} <- create_in_records(now, visitor) do
        names = %{
          coast_range: %{subdomain: subdomain()},
          silver_basin: %{subdomain: subdomain()},
          slug: "wesara-#{demo.id}"
        }

        build(demo, records, visitor, names, now)
      end

    tell(demo, result)
  end

  @doc """
  The dev teams (tools/dev-teams.exs): Coast Range SAR at `coastrange`, Silver Basin SAR
  at `silverbasin`, and WESARA at `wesara`, in the dev database, with a site admin
  `%{name:, email:}` as the visitor. No demo row, so they never expire and show no
  banner. SAR Duty admins open every organization, so the site admin isn't one of
  WESARA's. `{:ok, coast_range_team}` or `{:error, reason}`, with nothing left behind.
  """
  def build_dev_teams(%{name: _, email: _} = visitor, now) do
    with {:ok, records} <- create_in_records(now, visitor) do
      names = %{
        coast_range: %{subdomain: "coastrange"},
        silver_basin: %{subdomain: "silverbasin"},
        slug: "wesara"
      }

      build(nil, records, nil, names, now, visitor)
    end
  end

  defp tell(demo, result) do
    Phoenix.PubSub.broadcast(App.PubSub, topic(demo), {:demo_built, demo.id, result})
    result
  end

  defp visitor(demo),
    do: %{name: DemoTeam.visitor_name(demo), email: DemoTeam.visitor_email(demo)}

  # Both teams in Records, or neither. Coast Range's cast makes WESARA there, with its
  # fields, and Silver Basin's joins it, so it is made from Coast Range's answer.
  defp create_in_records(now, visitor) do
    with {:ok, coast} <- now |> DemoCast.cast(visitor) |> D4H.create_demo_team() do
      case create_silver_basin(now, coast) do
        {:ok, basin} ->
          {:ok, [coast, basin]}

        {:error, _error} = error ->
          D4H.delete_records_team(%Team{d4h_team_id: coast.d4h_team_id})
          error
      end
    end
  end

  defp create_silver_basin(now, coast) do
    now
    |> DemoCast.silver_basin(%{id: coast.organization_id, ids: coast.ids})
    |> D4H.create_demo_team()
  rescue
    # Records' answer lacked a field Silver Basin has values for.
    error in KeyError -> {:error, error |> Exception.message() |> D4H.Error.exception()}
  end

  # A visitor's days count from now, when they first see it. A test's keeps its hours.
  defp expires_at(%DemoTeam{kind: :visitor}, now),
    do: now |> DateTime.add(DemoTeam.days(), :day) |> DateTime.truncate(:second)

  defp expires_at(%DemoTeam{expires_at: expires_at}, _now), do: expires_at

  # `org_visitor` is who joins WESARA as an organization admin: a demo's visitor, or
  # nobody for the dev teams.
  defp build(demo, records, org_visitor, names, now, visitor \\ nil)

  defp build(demo, [coast, basin] = records, org_visitor, names, now, visitor) do
    visitor = visitor || org_visitor
    rows = CoastRange.build(now)
    team = insert_team(rows, demo, :team_id, coast, names.coast_range, now)
    team = refresh!(team)
    add_local_rows(team, coast.ids, visitor, now)
    mark_photos(team, coast.ids)
    team = put_contact(team, coast.ids)

    second =
      now
      |> SilverBasin.build()
      |> insert_team(demo, :second_team_id, basin, names.silver_basin, now)
      |> refresh!()

    insert_organization(demo, [team, second], names.slug, org_visitor, coast.organization_id)
    {:ok, team}
  rescue
    error ->
      Logger.error("Try a demo build failed: " <> Exception.message(error))
      clean_up(demo, records, names.slug)
      {:error, :build_failed}
  end

  defp refresh!(team) do
    case RefreshD4HData.call(team) do
      {:ok, refreshed, _missed} ->
        {:ok, team} = Team.update(refreshed, %{d4h_refresh_result: "OK"})
        team

      other ->
        raise("refresh: #{inspect(other)}")
    end
  end

  # DeleteTeam.purge/2 deletes a team in Records too, and Records deletes a demo at once.
  # A team Records made that SAR Duty never added goes from Records alone. Teams first:
  # Coast Range's delete takes the demo's row with it.
  defp clean_up(demo, records, slug) do
    demo = demo && Repo.reload(demo)
    if demo, do: DemoTeam |> where(id: ^demo.id) |> Repo.update_all(set: [team_id: nil])
    reason = if demo, do: :demo, else: :admin

    for %{d4h_team_id: d4h_team_id} <- records do
      case Repo.get_by(Team, d4h_api_host: D4H.records_host(), d4h_team_id: d4h_team_id) do
        %Team{} = team -> DeleteTeam.purge(team, reason: reason)
        nil -> D4H.delete_records_team(%Team{d4h_team_id: d4h_team_id})
      end
    end

    Organization |> where(slug: ^slug) |> Repo.delete_all()
  end

  # The team and its demo row's link commit together, so it is a demo before it has a
  # member. Coast Range's (`team_id`) starts the visitor's days.
  defp insert_team(rows, demo, field, records, names, now) do
    [{:team, _key, cast_team, []} | _rows] = rows

    {:ok, team} =
      Repo.transaction(fn ->
        team =
          Team.insert!(%{
            name: cast_team.name,
            legal_name: cast_team.legal_name,
            abbreviated_name: cast_team.abbreviated_name,
            subdomain: names.subdomain,
            d4h_team_id: records.d4h_team_id,
            d4h_api_host: D4H.records_host(),
            mailing_address: cast_team.mailing_address,
            lat: cast_team.lat,
            lng: cast_team.lng,
            timezone: cast_team.timezone,
            d4h_access_key: records.access_key,
            d4h_access_key_saved_at: now
          })

        retiring =
          cast_team.retiring_d4h_group_id &&
            records.ids[DemoCast.key({:group, cast_team.retiring_d4h_group_id})]

        team =
          team
          |> Ecto.Changeset.change(Map.take(cast_team, @settings))
          |> Ecto.Changeset.change(retiring_d4h_group_id: retiring)
          |> Repo.update!()

        if demo, do: link_demo(demo, field, team, now)
        team
      end)

    team
  end

  defp link_demo(demo, :team_id, team, now),
    do:
      demo
      |> Ecto.Changeset.change(team_id: team.id, expires_at: expires_at(demo, now))
      |> Repo.update!()

  defp link_demo(demo, field, team, _now),
    do: demo |> Ecto.Changeset.change([{field, team.id}]) |> Repo.update!()

  # WESARA's copy, with both teams in it, its two organization admins, a demo's visitor
  # beside them (the senior manager who opens both Coast Range and its space), and its
  # made-up forms, on.
  defp insert_organization(demo, teams, slug, visitor, records_organization_id) do
    {:ok, organization} =
      Repo.transaction(fn ->
        organization =
          Repo.insert!(%{
            CoastRange.organization()
            | slug: slug,
              records_organization_id: records_organization_id
          })

        Team
        |> where([t], t.id in ^Enum.map(teams, & &1.id))
        |> Repo.update_all(set: [organization_id: organization.id])

        visitors =
          if visitor, do: [%{email: visitor.email, title: "Your demo's visitor"}], else: []

        for admin <- CoastRange.organization_admins() ++ visitors do
          Repo.insert!(%OrganizationAdmin{
            organization_id: organization.id,
            email: admin.email,
            reason: admin.title
          })
        end

        AddDemoForms.call(organization)

        if demo do
          DemoTeam
          |> where(id: ^demo.id)
          |> Repo.update_all(set: [organization_id: organization.id])
        end

        organization
      end)

    organization
  end

  # Never a real team's: "demo" and 8 random letters and digits.
  defp subdomain do
    suffix = 5 |> :crypto.strong_rand_bytes() |> Base.encode32(case: :lower, padding: false)
    "demo" <> suffix
  end

  # Rows only SAR Duty keeps. Their links to synced rows go through Records' ids; links
  # between them, through the rows already added.
  defp add_local_rows(team, ids, visitor, now) do
    synced = %{
      member: by_d4h_id(Member, :d4h_member_id, team),
      tag: by_d4h_id(Tag, :d4h_tag_id, team),
      group: by_d4h_id(Group, :d4h_group_id, team),
      activity: by_d4h_id(Activity, :d4h_activity_id, team),
      equipment_item: by_d4h_id(EquipmentItem, :d4h_equipment_id, team)
    }

    _added =
      now
      |> DemoCast.local_rows(visitor)
      |> Enum.reduce(%{}, fn {kind, key, row, links}, added ->
        row = row |> localize(team, ids) |> put_links(links, ids, synced, added)
        Map.put(added, {kind, key}, Repo.insert!(row))
      end)

    :ok
  end

  # Demos skip the nightly photo check (#1012), so has_photo comes from the cast: each
  # person has the sample photo but the visitor (DemoCast). The visitor's prebuilt card
  # still works; their Replace asks for a photo, which Change member adds.
  defp mark_photos(team, ids) do
    query = where(Member, [m], m.team_id == ^team.id and not m.not_a_person)

    query =
      case ids[DemoCast.key({:member, :visitor})] do
        nil -> query
        visitor_id -> where(query, [m], m.d4h_member_id != ^visitor_id)
      end

    Repo.update_all(query, set: [has_photo: true])
  end

  # Get help goes to Alex Chen, as a team that picked its contacts has it (#780).
  defp put_contact(team, ids) do
    alex =
      Repo.get_by!(Member,
        team_id: team.id,
        d4h_member_id: ids[DemoCast.key({:member, "Alex Chen"})]
      )

    team |> Ecto.Changeset.change(first_contact_id: alex.id) |> Repo.update!()
  end

  defp by_d4h_id(schema, field, team) do
    schema
    |> where(team_id: ^team.id)
    |> Repo.all()
    |> Map.new(&{Map.fetch!(&1, field), &1.id})
  end

  # A card gets a real code, never a sample's (SAMP codes are only looked up in
  # App.SampleRepo), and a serial number of the team's own.
  defp localize(%MemberCard{} = card, team, _ids),
    do: %{
      card
      | team_id: team.id,
        code: MemberCard.generate_code(),
        serial_number: "#{team.subdomain}-#{card.serial_number}"
    }

  defp localize(%App.Model.EndorsementQualification{} = row, _team, ids),
    do: %{
      row
      | d4h_qualification_id: ids[DemoCast.key({:qualification, row.d4h_qualification_id})]
    }

  defp localize(%App.Model.ChoreEvent{} = row, team, ids),
    do: %{
      row
      | team_id: team.id,
        d4h_activity_id: ids[DemoCast.key({:activity, row.d4h_activity_id})]
    }

  defp localize(%GroupRule{} = row, team, ids),
    do: %{row | team_id: team.id, d4h_group_id: ids[DemoCast.key({:group, row.d4h_group_id})]}

  defp localize(%Template{} = row, team, ids),
    do: %{row | team_id: team.id, custom_values: DemoCast.local_values(row.custom_values, ids)}

  defp localize(%Trip{} = row, team, ids),
    do: %{
      row
      | team_id: team.id,
        d4h_attendance_id: ids[DemoCast.key({:attendance, row.d4h_attendance_id})]
    }

  defp localize(row, team, _ids),
    do: if(Map.has_key?(row, :team_id), do: %{row | team_id: team.id}, else: row)

  defp put_links(row, links, ids, synced, added) do
    Enum.reduce(links, row, fn {field, {kind, _key} = ref}, row ->
      id =
        case Map.fetch(synced, kind) do
          {:ok, by_d4h_id} -> Map.fetch!(by_d4h_id, Map.fetch!(ids, DemoCast.key(ref)))
          :error -> Map.fetch!(added, ref).id
        end

      Map.put(row, field, id)
    end)
  end
end
