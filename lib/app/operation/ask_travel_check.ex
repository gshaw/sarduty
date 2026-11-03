defmodule App.Operation.AskTravelCheck do
  @moduledoc """
  A team admin emails the members whose travel they set to check it (#230), from Travel.
  Never sent on its own. It goes to each member with a trip they haven't checked, an
  email, and a login: only a team with member logins on, and never a retiring member.
  Each is queued with SendActivityUpdate as a `:travel_check`, so a refusal is retried
  and a member who checked first gets nothing.
  """
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.ActivityUpdate
  alias App.Model.Member
  alias App.Model.Trip
  alias App.Operation.SendActivityUpdate
  alias App.Operation.SetTravel
  alias App.Repo
  alias Service.Format

  @doc "The members who would get the email: unchecked trips, an email, not retiring."
  def recipients(%Activity{} = activity) do
    ids =
      from(t in Trip,
        where: t.activity_id == ^activity.id and is_nil(t.checked_at),
        select: t.member_id
      )

    Member
    |> where([m], m.team_id == ^activity.team_id and m.id in subquery(ids))
    |> where([m], not is_nil(m.email) and m.email != "")
    |> Member.not_retiring_query()
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  @doc "When a team admin last asked, or nil."
  def last_asked(%Activity{} = activity) do
    ActivityUpdate
    |> where(
      [u],
      u.activity_id == ^activity.id and u.team_id == ^activity.team_id and u.kind == :travel_check
    )
    |> select([u], max(u.sent_at))
    |> Repo.one()
  end

  @doc """
  Queues the email to each of recipients/1: `{:ok, members}`, or `{:error, reason}`:
  :published, :deleted, :no_logins, or :nobody.
  """
  def call(team, %Activity{} = activity, user, now) do
    cond do
      activity.deleted_at -> {:error, :deleted}
      Activity.locked?(activity) -> {:error, :published}
      !team.member_logins -> {:error, :no_logins}
      true -> queue(activity, user, recipients(activity), now)
    end
  end

  defp queue(_activity, _user, [], _now), do: {:error, :nobody}

  defp queue(activity, user, members, now) do
    for member <- members,
        do: SendActivityUpdate.queue(activity, member, user, "", now, :travel_check)

    {:ok, members}
  end

  @doc "The toast."
  def result_text(members),
    do:
      "Emailed #{Format.count(length(members), one: "%d member", many: "%d members")} to check their travel."

  def error_text(_team, :nobody), do: "Everyone with travel set has checked it, or has no email."
  def error_text(_team, :no_logins), do: "Members can't log in to this team, so they can't check."
  def error_text(team, reason), do: SetTravel.error_text(team, reason)
end
