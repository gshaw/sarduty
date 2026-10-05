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
  alias App.Adapter.Twilio
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
      user = get_or_create_user(email)
      send_login_code(user, user.email)
    end

    :ok
  end

  @doc "Whether login codes can go out by text: Twilio is set up."
  def text_login?, do: Twilio.configured?()

  @doc """
  Texts a login code to an E.164 number, like deliver_login_code/1 does by email. The
  number must belong to exactly one email that may log in: D4H holds no other link from
  a number to an account, and a shared family number can't pick between two people.
  Returns `:ok` either way.
  """
  def deliver_login_text(phone) do
    if text_login?() do
      case text_login_email(phone) do
        nil -> nil
        email -> email |> get_or_create_user() |> send_login_code(phone)
      end
    end

    :ok
  end

  @doc "The one email that may log in with this number, or nil."
  def text_login_email(phone, now \\ DateTime.utc_now()) do
    case phone |> Member.current_emails_with_phone(now) |> Enum.filter(&may_log_in?(&1, now)) do
      [email] -> email
      _none_or_many -> nil
    end
  end

  defp get_or_create_user(email),
    do: get_user_by_email(email) || %{email: email} |> User.new_changeset() |> Repo.insert!()

  # The code goes to `sent_to`: the user's email, or an E.164 number for a text.
  defp send_login_code(user, sent_to) do
    unless recent_login_code?(user, sent_to) do
      user |> UserToken.by_user_and_contexts_query(["login"]) |> Repo.delete_all()
      {code, user_token} = UserToken.build_login_code(user, sent_to)
      Repo.insert!(user_token)

      if String.starts_with?(sent_to, "+"),
        do: UserNotifier.deliver_login_text(sent_to, code),
        else: UserNotifier.deliver_login_code(user, code)
    end
  end

  defp recent_login_code?(user, sent_to) do
    user
    |> UserToken.by_user_and_contexts_query(["login"])
    |> where([t], t.sent_to == ^sent_to and t.inserted_at > ago(60, "second"))
    |> Repo.exists?()
  end

  @doc """
  Logs in with an emailed code. A match uses it up; a miss counts against it, and the
  fifth miss kills it. `:error` for a wrong, used, or expired code, or an unknown email.
  """
  def log_in_with_code(email, code) when is_binary(email) and is_binary(code) do
    case get_user_by_email(email) do
      %User{} = user -> check_code(user, user.email, code)
      nil -> :error
    end
  end

  @doc """
  Logs in with a texted code, like log_in_with_code/2. Only a code texted to this number
  counts, and only while the number still leads to the same user.
  """
  def log_in_with_text_code(phone, code) when is_binary(phone) and is_binary(code) do
    with true <- text_login?(),
         email when is_binary(email) <- text_login_email(phone),
         %User{} = user <- get_user_by_email(email) do
      check_code(user, phone, code)
    else
      _ -> :error
    end
  end

  defp check_code(user, sent_to, code) do
    code = String.replace(code, ~r/\s/, "")

    case user |> UserToken.live_login_code_query(sent_to) |> Repo.one() do
      %UserToken{} = token ->
        if user |> UserToken.hash_code(code) |> Plug.Crypto.secure_compare(token.token) do
          user |> UserToken.by_user_and_contexts_query(["login"]) |> Repo.delete_all()
          {:ok, user}
        else
          UserToken |> where(id: ^token.id) |> Repo.update_all(inc: [failed_attempts: 1])
          :error
        end

      nil ->
        :error
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
