defmodule App.Operation.BuildDemoTeam do
  @moduledoc """
  Builds a visitor's copy of Coast Range SAR (#857) the first time they open their demo
  link, the way a team signs up. Records makes the team from the cast and picks its ids
  (App.DemoCast). SAR Duty then adds the team, marked as the demo before anything can
  send, refreshes it like any team, and adds what only SAR Duty keeps (endorsements, ID
  cards, away periods, chores), matched through Records' ids.

  A failure removes whatever was made, in Records too, so the next open starts clean.
  Runs in App.Worker.BuildDemoTeamWorker, and tells the waiting page through topic/1.
  """

  import Ecto.Query, only: [where: 2]

  alias App.Adapter.D4H
  alias App.CoastRange
  alias App.DemoCast
  alias App.Model.DemoTeam
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.DeleteTeam
  alias App.Operation.RefreshD4HData
  alias App.Repo

  require Logger

  # The team's settings from the cast, as a team that uses each feature has them.
  @settings [
    :name,
    :legal_name,
    :abbreviated_name,
    :mailing_address,
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

  @doc "`{:ok, team}`, or `{:error, reason}` with nothing left behind."
  def call(%DemoTeam{team_id: team_id}, _now) when is_integer(team_id),
    do: {:ok, Team.get!(team_id)}

  def call(%DemoTeam{} = demo, now) do
    result =
      with {:ok, key} <- demo_key(),
           {:ok, records} <- D4H.create_demo_team(key, DemoCast.cast(now, visitor(demo))) do
        build(demo, records, key, now)
      end

    Phoenix.PubSub.broadcast(App.PubSub, topic(demo), {:demo_built, demo.id, result})
    result
  end

  defp visitor(demo),
    do: %{name: DemoTeam.visitor_name(demo), email: DemoTeam.visitor_email(demo)}

  # A visitor's days count from now, when they first see it. A test's keeps its hours.
  defp expires_at(%DemoTeam{kind: :visitor}, now),
    do: now |> DateTime.add(DemoTeam.days(), :day) |> DateTime.truncate(:second)

  defp expires_at(%DemoTeam{expires_at: expires_at}, _now), do: expires_at

  defp demo_key do
    case Application.get_env(:sarduty, :records_demo_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _none -> {:error, :no_demo_key}
    end
  end

  defp build(demo, records, key, now) do
    team = insert_team(demo, records, now)
    {:ok, team} = team |> RefreshD4HData.call() |> refreshed(team)
    add_local_rows(team, records.ids, now)
    {:ok, team}
  rescue
    error ->
      Logger.error("Try a demo build failed: " <> Exception.message(error))
      clean_up(demo, records, key)
      {:error, :build_failed}
  end

  defp refreshed({:ok, refreshed, _missed}, _team) do
    Team.update(refreshed, %{d4h_refresh_result: "OK"})
  end

  defp refreshed(other, _team), do: raise("refresh: #{inspect(other)}")

  defp clean_up(demo, records, key) do
    case Repo.reload(demo) do
      %DemoTeam{team_id: team_id} when is_integer(team_id) ->
        team = Team.get!(team_id)
        DemoTeam |> where(id: ^demo.id) |> Repo.update_all(set: [team_id: nil])
        DeleteTeam.call(team, records: :delete_demo)

      _unbuilt ->
        D4H.delete_demo_team(key, records.d4h_team_id)
    end
  end

  # The team and its demo row commit together, so it is a demo before it has a member.
  defp insert_team(demo, records, now) do
    [{:team, :coastrange, cast_team, []} | _rows] = CoastRange.build(now)

    {:ok, team} =
      Repo.transaction(fn ->
        team =
          Team.insert!(%{
            name: cast_team.name,
            legal_name: cast_team.legal_name,
            abbreviated_name: cast_team.abbreviated_name,
            subdomain: subdomain(),
            d4h_team_id: records.d4h_team_id,
            d4h_api_host: D4H.records_host(),
            mailing_address: cast_team.mailing_address,
            lat: cast_team.lat,
            lng: cast_team.lng,
            timezone: cast_team.timezone,
            d4h_access_key: records.access_key,
            d4h_access_key_saved_at: now
          })

        retiring = records.ids[DemoCast.key({:group, cast_team.retiring_d4h_group_id})]

        team =
          team
          |> Ecto.Changeset.change(Map.take(cast_team, @settings))
          |> Ecto.Changeset.change(retiring_d4h_group_id: retiring)
          |> Repo.update!()

        demo
        |> Ecto.Changeset.change(team_id: team.id, expires_at: expires_at(demo, now))
        |> Repo.update!()

        team
      end)

    team
  end

  # Never a real team's: "demo" and 8 random letters and digits.
  defp subdomain do
    suffix = 5 |> :crypto.strong_rand_bytes() |> Base.encode32(case: :lower, padding: false)
    "demo" <> suffix
  end

  # Rows only SAR Duty keeps. Their links to synced rows go through Records' ids; links
  # between them, through the rows already added.
  defp add_local_rows(team, ids, now) do
    synced = %{
      member: by_d4h_id(Member, :d4h_member_id, team),
      tag: by_d4h_id(Tag, :d4h_tag_id, team)
    }

    _added =
      now
      |> DemoCast.local_rows()
      |> Enum.reduce(%{}, fn {kind, key, row, links}, added ->
        row = row |> localize(team, ids) |> put_links(links, ids, synced, added)
        Map.put(added, {kind, key}, Repo.insert!(row))
      end)

    :ok
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
