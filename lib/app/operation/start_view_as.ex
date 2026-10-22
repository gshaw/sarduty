defmodule App.Operation.StartViewAs do
  @moduledoc """
  Records a team admin starting to view the team as one of its members (#425), so
  /admin/events shows who looked at whose pages. Viewing changes nothing else: the pages
  are read-only and show no data the team admin couldn't already see.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Member

  def call(%User{} = user, %Member{} = member) do
    Event.record!(:member_viewed_as,
      team_id: member.team_id,
      user_id: user.id,
      data: %{member_id: member.id}
    )

    :ok
  end
end
