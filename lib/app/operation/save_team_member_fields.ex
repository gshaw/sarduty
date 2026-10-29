defmodule App.Operation.SaveTeamMemberFields do
  @moduledoc """
  Saves which of D4H's member custom fields a team copies (#681), from team settings'
  Members tab. Only fields CustomField.member_choices/1 offers can be picked: never a
  RESTRICTED one.

  Saving clears every member's copied values, so the next copy is the baseline and
  history doesn't list each member's value as a change, and a field no longer picked
  leaves nothing behind. Then the members are read from D4H at once, so the values show
  without waiting for the night's refresh.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.CustomField
  alias App.Model.Event
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.UpsertMembers
  alias App.Repo

  require Logger

  @doc "`d4h_ids` are the picked fields' D4H ids, as strings or integers. `:ok`."
  def call(%Team{} = team, d4h_ids, %User{} = user) do
    offered = team.id |> CustomField.member_choices() |> Enum.map(& &1.d4h_custom_field_id)
    picked = d4h_ids |> Enum.map(&to_integer/1) |> Enum.filter(&(&1 in offered))

    Repo.transaction(fn ->
      CustomField
      |> where([f], f.team_id == ^team.id and f.target == "member")
      |> Repo.update_all(set: [copy_values: false])

      CustomField
      |> where([f], f.team_id == ^team.id and f.d4h_custom_field_id in ^picked)
      |> Repo.update_all(set: [copy_values: true])

      Member
      |> where([m], m.team_id == ^team.id)
      |> Repo.update_all(set: [custom_values: nil])

      Event.record!(:member_fields_changed,
        team_id: team.id,
        user_id: user.id,
        data: %{d4h_custom_field_ids: picked}
      )
    end)

    read_members(team)
    :ok
  end

  defp to_integer(id) when is_integer(id), do: id

  defp to_integer(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _other -> nil
    end
  end

  # A failed read leaves the values for the next sync or the night's refresh.
  defp read_members(%Team{d4h_access_key: key} = team) when key not in [nil, ""] do
    team |> D4H.build_context_from_team() |> UpsertMembers.call(team, Progress.quiet(team.id))
  rescue
    error in D4H.Error ->
      Logger.warning("Member read failed for team #{team.id}: #{Exception.message(error)}")
  end

  defp read_members(_team), do: :ok
end
