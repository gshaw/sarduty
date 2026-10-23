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
  alias App.Repo

  @reply_salt "activity reply"
  @reminders_salt "invitation reminders"

  # Reminders go out before an activity, and its page closes at the start anyway.
  @reply_max_age 90 * 24 * 60 * 60
  # A mail app's unsubscribe keeps working for as long as people keep their email.
  @reminders_max_age 5 * 365 * 24 * 60 * 60

  @doc """
  A reply link. `answer`, `:yes` or `:no`, is the email button it sits behind: the page
  opens with it selected. It isn't signed, since the token is what allows a reply.
  """
  def reply_path(%Member{} = member, %Activity{} = activity, answer \\ nil) do
    path = "/replies/" <> Phoenix.Token.sign(Web.Endpoint, @reply_salt, [member.id, activity.id])

    case answer do
      nil -> path
      answer when answer in [:yes, :no] -> path <> "?reply=#{answer}"
    end
  end

  def reminders_path(%Member{} = member),
    do: "/reminders/" <> Phoenix.Token.sign(Web.Endpoint, @reminders_salt, member.id)

  @doc "`{:ok, {member_id, activity_id}}`, or `:error` for a token that is bad or too old."
  def verify_reply(token) when is_binary(token) do
    case Phoenix.Token.verify(Web.Endpoint, @reply_salt, token, max_age: @reply_max_age) do
      {:ok, [member_id, activity_id]} -> {:ok, {member_id, activity_id}}
      _error -> :error
    end
  end

  @doc """
  The member and the activity a reply token names, both on the same team, with the
  activity's team loaded. Nil for a token that is bad or too old.
  """
  def find_reply(token) do
    with {:ok, {member_id, activity_id}} <- verify_reply(token),
         %Member{} = member <- Repo.get(Member, member_id),
         %Activity{} = activity <- Activity.get_by(id: activity_id, team_id: member.team_id) do
      {member, Repo.preload(activity, :team)}
    else
      _missing -> nil
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
