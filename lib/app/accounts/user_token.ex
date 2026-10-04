defmodule App.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias App.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # A login link is single use and short-lived: anyone who can read the inbox can use it.
  @login_validity_in_minutes 15
  # 128 random bits: out of reach of guessing, and only the hash is stored. Written as
  # lowercase base32, it's 26 letters and digits, so the link stays short and plain.
  @login_rand_size 16
  @session_validity_in_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, App.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  A session token, kept in the signed session and remember-me cookie. Storing it lets a
  session be ended from the server.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc "The user a session token belongs to, if it's under 60 days old."
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  A login link token. The email gets the raw token; the database keeps only its hash,
  so a copy of the database can't be used to log in.
  """
  def build_login_token(user) do
    token = :crypto.strong_rand_bytes(@login_rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.encode32(token, case: :lower, padding: false),
     %UserToken{token: hashed_token, context: "login", sent_to: user.email, user_id: user.id}}
  end

  @doc """
  The query for a login token's user: the hash matches, it's under 15 minutes old, and
  the user's email hasn't changed since it was sent. `:error` for a malformed token.
  """
  def verify_login_token_query(token) do
    case Base.decode32(token, case: :mixed, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, "login"),
            join: user in assoc(token, :user),
            where:
              token.inserted_at > ago(@login_validity_in_minutes, "minute") and
                token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
