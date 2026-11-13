defmodule App.Operation.AddPasskey do
  @moduledoc """
  Saves a passkey a user just made in account settings (#129), and emails them that it
  was added. Someone who got into the account with one code could add their own passkey
  to keep coming back; the email is how the owner finds out.
  """

  alias App.Accounts.User
  alias App.Accounts.UserPasskey
  alias App.Accounts.WebAuthn
  alias App.Repo
  alias App.Worker.NotifyPasskeyAddedWorker

  @doc """
  `challenge` is the registration challenge the page made, `params` what the browser
  returned (App.Accounts.WebAuthn.register/2), and `user_agent` the browser's, to say
  what added it. `{:ok, passkey}`, or `{:error, :invalid | :taken}`.
  """
  def call(%User{} = user, challenge, params, user_agent) do
    with {:ok, attrs} <- register(challenge, params) do
      attrs = Map.put(attrs, :added_with, Service.UserAgent.describe(user_agent))
      insert(user, attrs)
    end
  end

  defp register(challenge, params) do
    case WebAuthn.register(challenge, params) do
      {:ok, attrs} -> {:ok, attrs}
      :error -> {:error, :invalid}
    end
  end

  defp insert(user, attrs) do
    Repo.transaction(fn ->
      case UserPasskey.insert(user, attrs) do
        {:ok, passkey} ->
          NotifyPasskeyAddedWorker.enqueue(passkey)
          passkey

        {:error, _changeset} ->
          Repo.rollback(:taken)
      end
    end)
  end
end
