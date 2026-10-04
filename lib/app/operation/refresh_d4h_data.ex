defmodule App.Operation.RefreshD4HData do
  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.RefreshD4HData
  alias App.Repo

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

  def error_message(:no_key), do: "No D4H key. Save a team key in Team Settings."

  def error_message({:key_rejected, status}),
    do: "D4H rejected the team key (#{status}). Save a new one in Team Settings."

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
    progress = refresh_team_data(d4h, team, progress)
    {tag_index, progress} = refresh_members_and_tags(d4h, team, progress)
    progress = refresh_all_activities(d4h, team, tag_index, progress)
    progress = refresh_qualifications(d4h, team, progress)
    progress = refresh_groups(d4h, team, progress)

    RefreshD4HData.Progress.complete(progress)
    {:ok, update_team_refreshed_at(team)}
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
