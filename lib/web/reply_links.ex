defmodule Web.ReplyLinks do
  @moduledoc """
  The signed links a reminder email holds (#444), which need no login. A reply link is
  for one member and one activity and only replies; its page closes at the start. A
  reminders link only turns that member's invitation reminders off or on. The token is
  the only access, so each does nothing else, and a token for one is no good for the
  other.
  """
  alias App.Model.Activity
  alias App.Model.Member

  @reply_salt "activity reply"
  @reminders_salt "invitation reminders"

  # Reminders go out before an activity, and its page closes at the start anyway.
  @reply_max_age 90 * 24 * 60 * 60
  # A mail app's unsubscribe keeps working for as long as people keep their email.
  @reminders_max_age 5 * 365 * 24 * 60 * 60

  def reply_path(%Member{} = member, %Activity{} = activity),
    do: "/replies/" <> Phoenix.Token.sign(Web.Endpoint, @reply_salt, [member.id, activity.id])

  def reminders_path(%Member{} = member),
    do: "/reminders/" <> Phoenix.Token.sign(Web.Endpoint, @reminders_salt, member.id)

  @doc "`{:ok, {member_id, activity_id}}`, or `:error` for a token that is bad or too old."
  def verify_reply(token) when is_binary(token) do
    case Phoenix.Token.verify(Web.Endpoint, @reply_salt, token, max_age: @reply_max_age) do
      {:ok, [member_id, activity_id]} -> {:ok, {member_id, activity_id}}
      _error -> :error
    end
  end

  @doc "`{:ok, member_id}`, or `:error` for a token that is bad or too old."
  def verify_reminders(token) when is_binary(token) do
    case Phoenix.Token.verify(Web.Endpoint, @reminders_salt, token, max_age: @reminders_max_age) do
      {:ok, member_id} when is_integer(member_id) -> {:ok, member_id}
      _error -> :error
    end
  end
end
