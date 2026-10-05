defmodule App.Operation.FollowUpNoShow do
  alias App.Accounts.User
  alias App.Model.NoShow
  alias App.Model.Team

  @doc "Marks a no-show followed up, or not. `{:ok, no_show}`, or `:error` for another team's."
  def call(%Team{} = team, no_show_id, followed_up, %User{} = user, now) do
    case NoShow.set_followed_up(team, no_show_id, followed_up, user, now) do
      nil -> :error
      no_show -> {:ok, no_show}
    end
  end
end
