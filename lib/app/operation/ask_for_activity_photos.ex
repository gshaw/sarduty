defmodule App.Operation.AskForActivityPhotos do
  @moduledoc """
  A team admin asks everyone who attended an activity for their photos of it (#1034).
  Each member gets an email whose button opens Add photos for that activity as them,
  with no login (Web.PhotoAskLinks). What they add waits for a team admin, as any
  member's photos do (App.Operation.AddActivityPhotos).

  plan/4 says who is asked and why the rest are not, pure. call/5 plans again, saves an
  ask per member (App.Model.ActivityPhotoAsk) and queues its email, in one transaction
  each. App.Worker.SendPhotoAskWorker sends each with deliver/3. Asking again later
  reaches whoever still has added none. SAR Duty asks nobody by itself, and sends no
  reminders.
  """
  import Ecto.Query

  alias App.Accounts.User
  alias App.Mailer.PhotoAskMailer
  alias App.Model.Activity
  alias App.Model.ActivityPhoto
  alias App.Model.ActivityPhotoAsk
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.AddActivityPhotos
  alias App.Operation.AskForPhoto
  alias App.Repo
  alias App.Validate.Message
  alias App.Worker.SendPhotoAskWorker

  @doc """
  Pure. Who gets an email, from `members`, and the ids of who attended, who added a
  photo to the activity, and who is retiring:

    * `send`: the members asked, in the members' order.
    * `left_out`: `[%{member:, reason:}]`, in the members' order.

  A member is left out when they did not attend (`:not_attended`), are retiring
  (`:retiring`), added a photo already (`:added`), have no email (`:no_email`), or
  turned these emails off (`:asks_off`). The first that fits is the reason.
  """
  def plan(members, attended_ids, added_ids, retiring_ids) do
    rows =
      for member <- members, do: {member, reason(member, attended_ids, added_ids, retiring_ids)}

    {send, left_out} = Enum.split_with(rows, fn {_member, reason} -> is_nil(reason) end)

    %{
      send: Enum.map(send, &elem(&1, 0)),
      left_out: for({member, reason} <- left_out, do: %{member: member, reason: reason})
    }
  end

  defp reason(member, attended_ids, added_ids, retiring_ids) do
    cond do
      not MapSet.member?(attended_ids, member.id) -> :not_attended
      MapSet.member?(retiring_ids, member.id) -> :retiring
      MapSet.member?(added_ids, member.id) -> :added
      member.email in [nil, ""] -> :no_email
      not member.photo_asks -> :asks_off
      true -> nil
    end
  end

  @doc """
  Whether a team admin asks for the activity's photos at `now`: the team has activity
  photos, and the activity takes them and has started. The one test, for the Photos
  tab's button, the ask page, and call/5. The activity needs
  Activity.put_logged_minutes/1.
  """
  def askable?(%Team{} = team, %Activity{} = activity, %DateTime{} = now),
    do: AddActivityPhotos.may_add?(team, activity, %{team_admin?: true, member: nil}, now)

  @doc """
  The plan for the activity as it stands now, from the team's current members on its
  list, A to Z.
  """
  def load_plan(%Team{id: team_id} = team, %Activity{team_id: team_id} = activity, now) do
    plan(
      listed(activity, now),
      attended_ids(activity, now),
      added_ids(activity),
      Standing.retiring_ids(team)
    )
  end

  # The team's current members with a row on the activity, whatever it says.
  defp listed(%Activity{id: activity_id, team_id: team_id}, now) do
    on_it = Attendance |> where([r], r.activity_id == ^activity_id) |> select([r], r.member_id)

    Member
    |> where([m], m.team_id == ^team_id and m.id in subquery(on_it))
    |> Member.current_query(now)
    |> order_by([m], asc: fragment("lower(?)", m.name), asc: m.id)
    |> Repo.all()
  end

  defp attended_ids(%Activity{id: activity_id}, now) do
    Attendance
    |> where([r], r.activity_id == ^activity_id)
    |> Attendance.attended(now)
    |> select([r], r.member_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # Who added a photo to the activity, waiting ones too.
  defp added_ids(%Activity{id: activity_id, team_id: team_id}) do
    ActivityPhoto
    |> where([p], p.team_id == ^team_id and p.activity_id == ^activity_id)
    |> where([p], not is_nil(p.member_id))
    |> select([p], p.member_id)
    |> distinct(true)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Asks everyone the plan sends to, from `user`, with their `message` or none.
  `{:ok, asks}`, which is `[]` when there is nobody to ask, `{:error, :not_askable}`
  for an activity askable?/3 refuses, or `{:error, :message_too_long}`.
  """
  def call(%Team{} = team, %Activity{} = activity, %User{} = user, message, now) do
    message = Message.normalize(message)

    cond do
      not askable?(team, activity, now) -> {:error, :not_askable}
      not Message.fits?(message) -> {:error, :message_too_long}
      true -> {:ok, ask_all(team, activity, user, message, now)}
    end
  end

  defp ask_all(team, activity, user, message, now) do
    %{send: send} = load_plan(team, activity, now)
    before = activity |> ActivityPhotoAsk.for_activity() |> Map.new(&{&1.member_id, &1})
    Enum.map(send, &ask(&1, before[&1.id], activity, user, message, now))
  end

  # The ask and its job commit together, or neither does. A member asked before keeps
  # their one ask, with this send's date and message.
  defp ask(member, before, activity, user, message, now) do
    new = %ActivityPhotoAsk{
      team_id: activity.team_id,
      activity_id: activity.id,
      member_id: member.id
    }

    {:ok, ask} =
      Repo.transaction(fn ->
        ask =
          (before || new)
          |> Ecto.Changeset.change(
            asked_by_user_id: user.id,
            message: message,
            asked_at: now,
            email_status: :queued
          )
          |> Repo.insert_or_update!()

        SendPhotoAskWorker.enqueue(ask)
        ask
      end)

    ask
  end

  @doc """
  Emails one ask and marks it sent, for its job. A refusal is `{:error, reason}`, so the
  job tries again; on the `last?` attempt the ask's email is marked failed first. An ask
  that is gone, whose member has no email now or turned these emails off since, or whose
  activity no longer takes their photos, is `{:cancel, reason}`. One already sent sends
  nothing, so a job that runs twice sends one email.
  """
  def deliver(ask_id, last?, now) do
    case ActivityPhotoAsk.get(ask_id) do
      nil -> {:cancel, "no ask"}
      %ActivityPhotoAsk{email_status: :queued} = ask -> send_email(ask, last?, now)
      %ActivityPhotoAsk{} -> :ok
    end
  end

  defp send_email(%ActivityPhotoAsk{member: member} = ask, last?, now) do
    cond do
      member.email in [nil, ""] ->
        ActivityPhotoAsk.set_email_status!(ask, :failed)
        {:cancel, "the member has no email"}

      not member.photo_asks ->
        {:cancel, "the member turned photo asks off"}

      not may_add?(ask, now) ->
        {:cancel, "the member can no longer add photos to the activity"}

      true ->
        mail(ask, last?, now)
    end
  end

  defp mail(%ActivityPhotoAsk{member: member, team: team} = ask, last?, now) do
    asker = AskForPhoto.asker(ask, now)
    url = Web.PhotoAskLinks.activity_url(ask)

    case PhotoAskMailer.deliver_activity(member, team, ask.activity, asker, ask.message, url) do
      {:ok, _sent} ->
        ActivityPhotoAsk.set_email_status!(ask, :sent)
        :ok

      {:error, error} ->
        if last?, do: ActivityPhotoAsk.set_email_status!(ask, :failed)
        {:error, error}
    end
  end

  @doc """
  Whether the ask's member may add photos to its activity at `now`
  (AddActivityPhotos.may_add?/4), and is still a member: current, and not retiring. What
  its email and its link both need. The ask comes from ActivityPhotoAsk.get/1.
  """
  def may_add?(%ActivityPhotoAsk{team: team, member: member, activity: activity}, now) do
    activity = Activity.put_logged_minutes(activity)
    retiring? = team |> Standing.retiring_ids() |> MapSet.member?(member.id)

    Member.current?(member, now) and not retiring? and
      AddActivityPhotos.may_add?(team, activity, %{team_admin?: false, member: member}, now)
  end

  @doc """
  The last time the team asked for the activity's photos, as the Photos tab says it:
  `%{count:, asked_at:}`, or nil when nobody was asked.
  """
  def last_ask(%Activity{} = activity),
    do: activity |> ActivityPhotoAsk.for_activity() |> ActivityPhotoAsk.last()

  @doc "What a call/5 error says."
  def error_text(:message_too_long), do: Message.error_text()
  def error_text(:not_askable), do: AddActivityPhotos.error_text(:kind)
end
