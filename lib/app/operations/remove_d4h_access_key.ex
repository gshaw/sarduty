defmodule App.Operation.RemoveD4HAccessKey do
  alias App.Accounts.User

  def call(user) do
    User.update!(user, %{
      d4h_access_key: nil,
      d4h_api_host: nil,
      d4h_changed_at: nil
    })
  end
end
