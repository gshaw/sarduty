defmodule App.Operation.RefreshD4HData do
  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Operation.RefreshD4HData
  alias App.Repo

  def call(%User{} = current_user) do
    team = current_user.team
    d4h = D4H.build_context_from_user(current_user)
    progress = RefreshD4HData.Progress.new(team.id)
    refresh(d4h, team, progress)
  end

  # A missing or rejected key needs a person to fix it, so it comes back as
  # `{:error, reason}` rather than an exception to retry and report.
  def call(%Team{} = team) do
    case RefreshD4HData.ResolveAccessKey.call(team) do
      nil -> {:error, :no_key}
      {key_owner, access_key} -> refresh_with_key(team, key_owner, access_key)
    end
  end

  def error_message(:no_key), do: "No D4H key. Save a team key in Team Settings."

  def error_message({:key_rejected, :team, status}),
    do: "D4H rejected the team key (#{status}). Save a new one in Team Settings."

  def error_message({:key_rejected, %User{email: email}, status}),
    do: "D4H rejected #{email}'s personal key (#{status}). Save a team key in Team Settings."

  defp refresh_with_key(team, key_owner, access_key) do
    d4h =
      D4H.build_context(
        access_key: access_key,
        api_host: team.d4h_api_host,
        d4h_team_id: team.d4h_team_id
      )

    progress = RefreshD4HData.Progress.new(team.id)
    refresh(d4h, team, progress)
  rescue
    error in D4H.Error ->
      if error.status in [401, 403] do
        {:error, {:key_rejected, key_owner, error.status}}
      else
        reraise error, __STACKTRACE__
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

    progress = RefreshD4HData.Progress.update_stage(progress, "Qualification Awards")
    {_count, progress} = RefreshD4HData.UpsertQualificationAwards.call(d4h, team, progress)
    RefreshD4HData.Progress.finish_stage(progress)
  end

  defp refresh_groups(d4h, team, progress) do
    progress = RefreshD4HData.Progress.update_stage(progress, "Groups")
    {_count, progress} = RefreshD4HData.UpsertGroups.call(d4h, team, progress)
    progress = RefreshD4HData.Progress.finish_stage(progress)

    progress = RefreshD4HData.Progress.update_stage(progress, "Group Memberships")
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
    case D4H.fetch_team_image(d4h) do
      {:ok, data, _filename} ->
        logo_path = Team.logo_path(team.subdomain)
        logo_dir_path = Path.dirname(logo_path)
        File.mkdir_p!(logo_dir_path)
        File.write!(logo_path, data)

      {:error, response} ->
        raise D4H.Error, response
    end
  end
end
