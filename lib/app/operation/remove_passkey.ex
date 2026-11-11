defmodule App.Operation.RemovePasskey do
  @moduledoc """
  Removes one of a user's passkeys (#129), so it can no longer log them in. The browser
  or password manager still holds its copy until the person deletes it there.
  """

  alias App.Accounts.User
  alias App.Accounts.UserPasskey
  alias App.Repo

  @doc "Only a passkey of `user`'s. `{:ok, passkey}`, or `:error` when it isn't theirs."
  def call(%User{} = user, id) do
    case UserPasskey.get_for(user, id) do
      %UserPasskey{} = passkey -> Repo.delete(passkey)
      nil -> :error
    end
  end
end
