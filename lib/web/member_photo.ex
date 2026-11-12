defmodule Web.MemberPhoto do
  @moduledoc """
  Where a member's photo is, for an `<img>`: the team's `/members/:id/image` route, which
  a browser keeps for an hour. The path carries when SAR Duty last changed the photo
  (#1028), so one just saved shows at once, and a page of 85 members asks the team's
  records once an hour, not on each visit.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  alias App.Model.Member
  alias App.Model.Team

  def path(%Team{} = team, %Member{photo_changed_at: nil} = member),
    do: ~p"/teams/#{team}/members/#{member.id}/image"

  def path(%Team{} = team, %Member{photo_changed_at: changed_at} = member),
    do: ~p"/teams/#{team}/members/#{member.id}/image?#{[v: DateTime.to_unix(changed_at)]}"
end
