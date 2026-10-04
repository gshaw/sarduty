defmodule App.Accounts do
  @moduledoc """
  Users and their login links and sessions. A user is an email that may log in: an
  admin, or a manager of some team in D4H (#57). Which teams they reach is
  App.Model.Team.get_managed_by/2.
  """

  import Ecto.Query, warn: false

  alias App.Accounts.User
  alias App.Accounts.UserNotifier
  alias App.Accounts.UserToken
  alias App.Model.Team
  alias App.Repo

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    email = normalize(email)

    User
    |> where([u], fragment("lower(?)", u.email) == ^email)
    |> Repo.one()
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
  Whether this email may log in: an admin's, or a current manager's on some team.
  """
  def may_log_in?(email, now \\ DateTime.utc_now()) do
    case get_user_by_email(email) do
      %User{is_admin: true} -> true
      _user -> Team.get_managed_by(email, now) != []
    end
  end

  @doc """
  Emails a login link when the email may log in, making its user on first use. Does
  nothing otherwise, and returns `:ok` either way, so the page never says which emails
  are known.
  """
  def deliver_login_link(email, url_fun) when is_function(url_fun, 1) do
    if may_log_in?(email) do
      user = get_user_by_email(email) || %{email: email} |> User.new_changeset() |> Repo.insert!()
      {encoded_token, user_token} = UserToken.build_login_token(user)
      Repo.insert!(user_token)
      UserNotifier.deliver_login_link(user, url_fun.(encoded_token))
    end

    :ok
  end

  @doc "The user a login token is for, without using it up. Nil when invalid or expired."
  def get_user_by_login_token(token) do
    case UserToken.verify_login_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  @doc """
  Uses up a login token: deletes every login token the user has, so each link works
  once, and confirms the email.
  """
  def log_in_with_token(token) do
    case get_user_by_login_token(token) do
      nil ->
        :error

      user ->
        user |> UserToken.by_user_and_contexts_query(["login"]) |> Repo.delete_all()
        {:ok, user |> User.confirm_changeset() |> Repo.update!()}
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
