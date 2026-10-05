defmodule App.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias App.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # A login code is single use and short-lived: anyone who can read the inbox can use it.
  # Six digits are guessable, so a code dies after 5 wrong tries, and Web.LoginLimit caps
  # misses per email and IP across codes.
  @login_validity_in_minutes 15
  @login_max_attempts 5
  @session_validity_in_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :failed_attempts, :integer, default: 0
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
  A six-digit login code. The email gets the code; the database keeps only its hash.
  """
  def build_login_code(user) do
    <<n::32>> = :crypto.strong_rand_bytes(4)
    code = n |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")

    {code,
     %UserToken{
       token: hash_code(user, code),
       context: "login",
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  A code's hash, keyed with the app's secret: a million codes are quick to try against
  a plain hash, so a copy of the database alone mustn't be enough.
  """
  # cspell:ignore hmac -- the :crypto.mac/4 algorithm name
  def hash_code(user, code) do
    secret = Application.fetch_env!(:sarduty, Web.Endpoint)[:secret_key_base]
    :crypto.mac(:hmac, @hash_algorithm, secret, "#{user.id}:#{code}")
  end

  @doc """
  The user's live login code: under 15 minutes old, under 5 wrong tries, and sent to the
  email the user still has.
  """
  def live_login_code_query(user) do
    from t in UserToken,
      where:
        t.user_id == ^user.id and t.context == "login" and t.sent_to == ^user.email and
          t.inserted_at > ago(@login_validity_in_minutes, "minute") and
          t.failed_attempts < @login_max_attempts,
      order_by: [desc: t.id],
      limit: 1
  end

  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
