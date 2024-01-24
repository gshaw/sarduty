defmodule App.Operation.RemoveD4HAccessKey do
  alias App.Accounts.User

  def call(user) do
    User.update!(user, %{team_id: nil, d4h_access_key: nil})
  end
end
