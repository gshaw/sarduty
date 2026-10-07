defmodule App.Operation.UpdateTeamSettings do
  import Ecto.Changeset

  alias App.Adapter.D4H
  alias App.Adapter.D4H.WhoAmI
  alias App.Model.Team
  alias App.Operation.SyncD4HChanges
  alias App.Repo

  def call(%Team{} = team, params) do
    changeset = Team.build_settings_changeset(team, params)
    new_key = get_change(changeset, :new_d4h_access_key)

    changeset =
      if changeset.valid? and new_key do
        check_new_key(changeset, team, fetch_whoami(team, new_key), DateTime.utc_now())
      else
        changeset
      end

    # The typed key is applied to the returned struct too; clear it so a form
    # rebuilt from this team renders the field blank.
    with {:ok, team} <- Repo.update(changeset) do
      {:ok, %{team | new_d4h_access_key: nil}}
    end
  end

  @doc """
  Saves the new key only if D4H says it belongs to a member of this team.
  A blank key field never gets here, so it keeps the saved key.
  """
  def check_new_key(changeset, %Team{} = team, {:ok, whoami}, now) do
    if team.d4h_team_id in whoami.d4h_team_ids do
      changeset
      |> put_change(:d4h_access_key, get_change(changeset, :new_d4h_access_key))
      |> put_change(:d4h_access_key_saved_at, now)
      |> put_change(:d4h_access_key_owner, WhoAmI.member_name(whoami, team.d4h_team_id))
      |> put_change(:d4h_access_key_member_id, WhoAmI.member_id(whoami, team.d4h_team_id))
      |> put_change(:d4h_sync_state, SyncD4HChanges.forget_key_rejected(team.d4h_sync_state))
    else
      add_error(
        changeset,
        :new_d4h_access_key,
        "Use a D4H access key for this team. This one is for another team."
      )
    end
  end

  def check_new_key(changeset, _team, {:error, :unreachable}, _now) do
    add_error(changeset, :new_d4h_access_key, "D4H did not respond. Try again in a few minutes.")
  end

  def check_new_key(changeset, _team, {:error, _reason}, _now) do
    add_error(
      changeset,
      :new_d4h_access_key,
      "Paste the key again. D4H does not accept this one."
    )
  end

  defp fetch_whoami(team, access_key) do
    D4H.fetch_whoami(access_key: access_key, api_host: team.d4h_api_host)
  rescue
    Req.TransportError -> {:error, :unreachable}
  end
end
