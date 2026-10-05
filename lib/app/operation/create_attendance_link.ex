defmodule App.Operation.CreateAttendanceLink do
  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.Team
  alias App.Repo

  @doc """
  A new link for taking attendance at `activity`. It closes the activity's older links,
  so a link sent to the wrong person stops working when you make another.
  """
  def call(%Team{} = team, %Activity{team_id: team_id} = activity, %User{} = user, now)
      when team_id == team.id do
    token = AttendanceLink.generate_token()

    {:ok, link} =
      Repo.transaction(fn ->
        AttendanceLink.close_all!(team, activity, now)

        AttendanceLink.insert!(%AttendanceLink{
          team_id: team.id,
          activity_id: activity.id,
          created_by_user_id: user.id,
          token: token,
          token_hash: AttendanceLink.hash_token(token)
        })
      end)

    Repo.preload(link, activity: :team)
  end
end
