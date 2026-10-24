defmodule App.Operation.SetTeamMemberLogins do
  @moduledoc """
  Turns member logins on or off for a team (#156). A team admin does this from the
  team's settings. Off ends access at once: a member's next page is a 404, since every
  member page checks the switch. `chores:` turns chores (#341) on or off with it, and
  `certificates:` members sending certificates (#493).
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, enabled, %User{} = user, opts \\ []) when is_boolean(enabled) do
    chores = Keyword.get(opts, :chores, false)
    certificates = Keyword.get(opts, :certificates, false)

    Repo.transaction(fn ->
      team =
        team
        |> Ecto.Changeset.change(
          member_logins: enabled,
          chores_enabled: chores,
          certificates_enabled: certificates
        )
        |> Repo.update!()

      kind = if enabled, do: :member_logins_turned_on, else: :member_logins_turned_off
      Event.record!(kind, team_id: team.id, user_id: user.id)
      team
    end)
  end
end
