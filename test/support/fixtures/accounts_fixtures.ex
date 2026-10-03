defmodule App.AccountsFixtures do
  @moduledoc """
  Test helpers for users. A user reaches a team only through a manager member with the
  same email; App.DataFixtures.user_with_team_fixture/1 makes both.
  """

  alias App.Accounts.User
  alias App.Repo

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def user_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %{email: attrs[:email] || unique_user_email()}
    |> User.new_changeset()
    |> Ecto.Changeset.change(Map.drop(attrs, [:email]))
    |> Repo.insert!()
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
