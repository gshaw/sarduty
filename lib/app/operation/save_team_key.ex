defmodule App.Operation.SaveTeamKey do
  @moduledoc """
  Access key's Replace the key (#727). Saves the new key only if D4H says it belongs to
  a member of this team, with what D4H lets it do, and records a `team_key_changed`
  event by `user`.
  """
  import Ecto.Changeset

  alias App.Adapter.D4H
  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.CheckTeamKey
  alias App.Operation.SyncD4HChanges
  alias App.Repo

  def call(%Team{} = team, params, user) do
    changeset = Team.build_key_changeset(team, params)

    changeset =
      if changeset.valid? do
        new_key = get_change(changeset, :new_d4h_access_key)
        whoami = D4H.fetch_whoami(access_key: new_key, api_host: team.d4h_api_host)
        check_new_key(changeset, team, whoami, DateTime.utc_now())
      else
        changeset
      end

    # The typed key is applied to the returned struct too; clear it so a form
    # rebuilt from this team renders the field blank.
    with {:ok, team} <- Repo.update(changeset) do
      record_key_changed(team, user)
      {:ok, %{team | new_d4h_access_key: nil}}
    end
  end

  @doc "Pure. The changeset with the new key saved, or an error on the key field."
  def check_new_key(changeset, %Team{} = team, {:ok, whoami}, now) do
    if team.d4h_team_id in whoami.d4h_team_ids do
      changeset
      |> put_change(:d4h_access_key, get_change(changeset, :new_d4h_access_key))
      |> put_change(:d4h_access_key_saved_at, now)
      |> change(CheckTeamKey.changes(whoami, team.d4h_team_id, now))
      |> put_change(:d4h_sync_state, SyncD4HChanges.forget_key_rejected(team.d4h_sync_state))
    else
      add_error(
        changeset,
        :new_d4h_access_key,
        "Use a #{D4H.key_name(team)} for this team. This one is for another team."
      )
    end
  end

  def check_new_key(changeset, team, {:error, :unreachable}, _now) do
    add_error(
      changeset,
      :new_d4h_access_key,
      "#{D4H.service_name(team)} did not answer. Try again in a few minutes."
    )
  end

  def check_new_key(changeset, team, {:error, :refused}, _now) do
    add_error(
      changeset,
      :new_d4h_access_key,
      "Paste the key again. #{D4H.service_name(team)} refused this one."
    )
  end

  defp record_key_changed(team, user) do
    Event.record!(:team_key_changed,
      team_id: team.id,
      user_id: user && user.id,
      data: %{sar_duty_account: Team.key_owner_is_sar_duty?(team)}
    )
  end
end
