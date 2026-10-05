defmodule App.Operation.CreateAttendanceLink do
  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.ShortLink
  alias App.Model.Team
  alias App.Repo

  @doc """
  A new link for taking attendance at `activity`, with a short link to it. It closes the
  activity's older links, so a link sent to the wrong person stops working when you make
  another.
  """
  def call(%Team{} = team, %Activity{team_id: team_id} = activity, %User{} = user, now)
      when team_id == team.id do
    token = AttendanceLink.generate_token()
    # The link's 30 days count from here, so it's stored as made, to the microsecond.
    {microsecond, _precision} = now.microsecond
    made_at = %{now | microsecond: {microsecond, 6}}

    {:ok, link} =
      Repo.transaction(fn ->
        AttendanceLink.close_all!(team, activity, made_at)

        short_link =
          ShortLink.create!("/attendance/#{token}",
            team_id: team.id,
            expires_at: AttendanceLink.expires_at(made_at)
          )

        AttendanceLink.insert!(%AttendanceLink{
          team_id: team.id,
          activity_id: activity.id,
          created_by_user_id: user.id,
          short_link_id: short_link.id,
          token: token,
          token_hash: AttendanceLink.hash_token(token),
          inserted_at: made_at,
          updated_at: made_at
        })
      end)

    Repo.preload(link, [:short_link, activity: :team])
  end
end
