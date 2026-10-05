defmodule App.Accounts do
  @moduledoc """
  Users and their login codes and sessions. A user is an email that may log in: a
  manager of some team in D4H (#57), or an admin who is a current member of one (#141).
  Which teams they reach is App.Model.Team.get_managed_by/2.
  """

  import Ecto.Query, warn: false

  alias App.Accounts.User
  alias App.Accounts.UserNotifier
  alias App.Accounts.UserToken
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    email = normalize(email)

    User
    |> where([u], fragment("lower(?)", u.email) == ^email)
    |> Repo.one()
  end

  @doc "Every admin, by email."
  def get_admins do
    User |> where([u], u.is_admin) |> order_by([u], u.email) |> Repo.all()
  end

  @doc "Every admin's email, for notices like a new team signing up."
  def admin_emails do
    User |> where([u], u.is_admin) |> select([u], u.email) |> Repo.all()
  end

  @doc "Which of these emails have a user, lowercase, as a MapSet."
  def login_emails(emails) do
    emails = for e <- emails, is_binary(e), do: normalize(e)

    User
    |> where([u], fragment("lower(?)", u.email) in ^emails)
    |> select([u], fragment("lower(?)", u.email))
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Whether this email may log in: a current manager's on some team, or an admin's that
  D4H still lists as a current member somewhere. Being an admin alone isn't enough, so
  every login stands on D4H (#141).
  """
  def may_log_in?(email, now \\ DateTime.utc_now()) do
    case get_user_by_email(email) do
      %User{is_admin: true} -> Member.current_email?(email, now)
      _user -> Team.get_managed_by(email, now) != []
    end
  end

  @doc """
  Emails a login code when the email may log in, making its user on first use. Does
  nothing otherwise, and returns `:ok` either way, so the page never says which emails
  are known. A code sent in the last minute stands, so a double tap sends one email; a
  later request replaces it.
  """
  def deliver_login_code(email) do
    if may_log_in?(email) do
      user = get_user_by_email(email) || %{email: email} |> User.new_changeset() |> Repo.insert!()

      unless recent_login_code?(user) do
        user |> UserToken.by_user_and_contexts_query(["login"]) |> Repo.delete_all()
        {code, user_token} = UserToken.build_login_code(user)
        Repo.insert!(user_token)
        UserNotifier.deliver_login_code(user, code)
      end
    end

    :ok
  end

  defp recent_login_code?(user) do
    user
    |> UserToken.by_user_and_contexts_query(["login"])
    |> where([t], t.inserted_at > ago(60, "second"))
    |> Repo.exists?()
  end

  @doc """
  Logs in with an emailed code. A match uses it up; a miss counts against it, and the
  fifth miss kills it. `:error` for a wrong, used, or expired code, or an unknown email.
  """
  def log_in_with_code(email, code) when is_binary(email) and is_binary(code) do
    code = String.replace(code, ~r/\s/, "")

    with %User{} = user <- get_user_by_email(email),
         %UserToken{} = token <- user |> UserToken.live_login_code_query() |> Repo.one() do
      if user |> UserToken.hash_code(code) |> Plug.Crypto.secure_compare(token.token) do
        user |> UserToken.by_user_and_contexts_query(["login"]) |> Repo.delete_all()
        {:ok, user}
      else
        UserToken |> where(id: ^token.id) |> Repo.update_all(inc: [failed_attempts: 1])
        :error
      end
    else
      _ -> :error
    end
  end

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    token |> UserToken.by_token_and_context_query("session") |> Repo.delete_all()
    :ok
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
