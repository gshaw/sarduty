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

  @doc "Sends a login code to the email through the test mailer and returns it."
  def login_code_fixture(email) do
    :ok = App.Accounts.deliver_login_code(email)

    receive do
      {:email, %{subject: "Your SAR Duty login code: " <> code}} -> code
    after
      0 -> raise "no login code was sent to #{email}"
    end
  end
end
