defmodule App.Operation.RefreshD4HData do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.RecordD4HChanges
  alias App.Operation.RefreshD4HData
  alias App.Operation.SyncD4HChanges
  alias App.Repo

  require Logger

  # A missing or rejected key needs a person to fix it, so it comes back as
  # `{:error, reason}` rather than an exception to retry and report.
  def call(%Team{d4h_access_key: key}) when key in [nil, ""], do: {:error, :no_key}

  def call(%Team{} = team) do
    team = record_key_owner(team)
    d4h = D4H.build_context_from_team(team)
    progress = RefreshD4HData.Progress.new(team.id)
    refresh(d4h, team, progress)
  rescue
    error in D4H.Error ->
      if error.status in [401, 403] do
        {:error, {:key_rejected, error.status}}
      else
        reraise error, __STACKTRACE__
      end
  end

  def error_message(:no_key), do: "No D4H access key. Save one in team settings."

  def error_message({:key_rejected, status}),
    do: "D4H rejected your D4H access key (#{status}). Save a new one in team settings."

  # Keys saved before the owner was recorded get it here. A rejected key is left for the
  # refresh's own requests to report.
  defp record_key_owner(team) do
    case D4H.fetch_whoami(access_key: team.d4h_access_key, api_host: team.d4h_api_host) do
      {:ok, whoami} ->
        params = %{
          d4h_access_key_owner: D4H.WhoAmI.member_name(whoami, team.d4h_team_id),
          d4h_access_key_member_id: D4H.WhoAmI.member_id(whoami, team.d4h_team_id)
        }

        team |> Team.build_changeset(params) |> Repo.update!()

      {:error, _reason} ->
        team
    end
  end

  @activity_types ["exercises", "events", "incidents"]

  defp refresh(d4h, team, progress) do
    started_at = DateTime.utc_now()
    # Seen before any stage, so the next sync fetches whatever changes while this runs.
    heads = SyncD4HChanges.fetch_heads(d4h)

    RecordD4HChanges.recording(team, started_at, fn ->
      progress = refresh_team_data(d4h, team, progress)
      {tag_index, progress} = refresh_members_and_tags(d4h, team, progress)
      progress = refresh_all_activities(d4h, team, tag_index, progress)
      progress = refresh_qualifications(d4h, team, progress)
      progress = refresh_groups(d4h, team, progress)
      RefreshD4HData.Progress.complete(progress)
    end)

    missed = count_corrections(team.id, started_at)
    team = team.id |> Team.get!() |> SyncD4HChanges.save_heads(heads, started_at)
    {:ok, update_team_refreshed_at(team), missed}
  end

  # What this refresh changed that the syncs every 10 minutes missed: rows written since
  # it started. If it stays at zero for a month, run it weekly (#163). Deletes are logged
  # by each stage. Returns the counts, by name.
  defp count_corrections(team_id, started_at) do
    member_ids = from(m in Member, where: m.team_id == ^team_id, select: m.id)

    counts = [
      members: where(Member, team_id: ^team_id),
      activities: where(Activity, team_id: ^team_id),
      attendance: where(Attendance, [a], a.member_id in subquery(member_ids)),
      qualifications: where(Qualification, team_id: ^team_id),
      awards: where(MemberQualificationAward, [a], a.member_id in subquery(member_ids)),
      groups: where(Group, team_id: ^team_id),
      group_members: where(GroupMember, [g], g.member_id in subquery(member_ids))
    ]

    missed =
      Map.new(counts, fn {name, query} ->
        {name, query |> where([r], r.updated_at >= ^started_at) |> Repo.aggregate(:count)}
      end)

    summary = Enum.map_join(counts, ", ", fn {name, _query} -> "#{name} #{missed[name]}" end)
    Logger.info("Full refresh of team #{team_id} wrote rows the syncs missed: #{summary}")
    missed
  end

  defp refresh_team_data(d4h, team, progress) do
    progress = RefreshD4HData.Progress.update_stage(progress, "Team logo")
    save_team_logo(d4h, team)
    RefreshD4HData.Progress.finish_stage(progress)
  end

  defp refresh_members_and_tags(d4h, team, progress) do
    progress = RefreshD4HData.Progress.update_stage(progress, "Members")
    {_count, progress} = RefreshD4HData.UpsertMembers.call(d4h, team, progress)
    progress = RefreshD4HData.Progress.finish_stage(progress)

    progress = RefreshD4HData.Progress.update_stage(progress, "Tags")
    tag_index = build_d4h_tag_index(d4h)
    progress = RefreshD4HData.Progress.finish_stage(progress)

    {tag_index, progress}
  end

  defp refresh_all_activities(d4h, team, tag_index, progress) do
    Enum.reduce(@activity_types, progress, fn kind, prog ->
      refresh_activities_by_type(d4h, team, tag_index, kind, prog)
    end)
  end

  defp refresh_activities_by_type(d4h, team, tag_index, kind, progress) do
    progress = RefreshD4HData.Progress.update_stage(progress, String.capitalize(kind))

    {_count, progress} =
      RefreshD4HData.UpsertActivities.call(d4h, team, tag_index, kind, progress)

    RefreshD4HData.Progress.finish_stage(progress)
  end

  defp refresh_qualifications(d4h, team, progress) do
    progress = RefreshD4HData.Progress.update_stage(progress, "Attendances")
    {_count, progress} = RefreshD4HData.UpsertAttendances.call(d4h, team, progress)
    progress = RefreshD4HData.Progress.finish_stage(progress)

    progress = RefreshD4HData.Progress.update_stage(progress, "Qualifications")
    {_count, progress} = RefreshD4HData.UpsertQualifications.call(d4h, team, progress)
    progress = RefreshD4HData.Progress.finish_stage(progress)

    progress = RefreshD4HData.Progress.update_stage(progress, "Qualification awards")
    {_count, progress} = RefreshD4HData.UpsertQualificationAwards.call(d4h, team, progress)
    RefreshD4HData.Progress.finish_stage(progress)
  end

  defp refresh_groups(d4h, team, progress) do
    progress = RefreshD4HData.Progress.update_stage(progress, "Groups")
    {_count, progress} = RefreshD4HData.UpsertGroups.call(d4h, team, progress)
    progress = RefreshD4HData.Progress.finish_stage(progress)

    progress = RefreshD4HData.Progress.update_stage(progress, "Group memberships")
    {_count, progress} = RefreshD4HData.UpsertGroupMemberships.call(d4h, team, progress)
    RefreshD4HData.Progress.finish_stage(progress)
  end

  defp build_d4h_tag_index(d4h) do
    d4h
    |> D4H.fetch_tags()
    |> Enum.map(fn r -> {r.d4h_tag_id, r.title} end)
    |> Map.new()
  end

  defp update_team_refreshed_at(team) do
    changeset = Team.build_changeset(team, %{d4h_refreshed_at: DateTime.utc_now()})
    Repo.update!(changeset)
  end

  defp save_team_logo(d4h, team) do
    logo_path = Team.logo_path(team.subdomain)

    case D4H.fetch_team_image(d4h) do
      {:ok, data, _filename} ->
        logo_path |> Path.dirname() |> File.mkdir_p!()
        File.write!(logo_path, data)

      # The team removed its image in D4H, so drop the one saved before.
      :none ->
        File.rm(logo_path)

      {:error, response} ->
        raise D4H.Error, response
    end
  end
end
