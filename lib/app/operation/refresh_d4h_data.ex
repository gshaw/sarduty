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

  def call(%Team{} = team) do
    access_key = RefreshD4HData.ResolveAccessKey.call(team)

    d4h =
      D4H.build_context(
        access_key: access_key,
        api_host: team.d4h_api_host,
        d4h_team_id: team.d4h_team_id
      )

    progress = RefreshD4HData.Progress.new(team.id)
    refresh(d4h, team, progress)
  end

  @activity_types ["exercises", "events", "incidents"]

  defp refresh(d4h, team, progress) do
    progress = refresh_team_data(d4h, team, progress)
    {tag_index, progress} = refresh_members_and_tags(d4h, team, progress)
    progress = refresh_all_activities(d4h, team, tag_index, progress)
    progress = refresh_qualifications(d4h, team, progress)

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
    end
  end
end
