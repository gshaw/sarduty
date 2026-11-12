defmodule App.Operation.AskForPhoto do
  @moduledoc """
  A team admin asks a member for a photo (#1030), or everyone with no photo at once. The
  member gets an email whose button opens Add a photo with no login (Web.PhotoAskLinks),
  and the photo they add waits for a team admin, as any member's own does
  (App.Operation.AddOwnPhoto).

  plan/4 says who is asked and why the rest are not, pure. call/5 plans again, saves an
  ask per member (App.Model.PhotoAsk) and queues its email, in one transaction each.
  App.Worker.SendPhotoAskWorker sends each with deliver/3. The ask is open until the
  member's photo is added, by them or a team admin. Asking a member again moves their
  ask's date and sends another email. SAR Duty asks nobody by itself, and sends no
  reminders.
  """
  alias App.Accounts.User
  alias App.Mailer.PhotoAskMailer
  alias App.Model.Member
  alias App.Model.PhotoAsk
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Operation.CleanUpPhoto
  alias App.Repo
  alias App.Validate.Message
  alias App.Worker.SendPhotoAskWorker

  @doc """
  Pure. Who gets an email, from `members`, the team's open `asks`, and its retiring ids:

    * `send`: `[%{member:, ask:}]`, with the member's open ask or nil.
    * `left_out`: `[%{member:, reason:, ask:}]`, in the members' order.

  `:everyone` leaves out a member with a photo (`:has_photo`) and one with an open ask
  (`:asked`). `:one` is a team admin picking the member, so it asks them all the same: for
  a new photo, or again. Either leaves out a member who is not a person
  (`:not_a_person`), is retiring (`:retiring`), or has no email (`:no_email`).
  """
  def plan(members, asks, retiring_ids, scope) when scope in [:everyone, :one] do
    asks = Map.new(asks, &{&1.member_id, &1})

    rows =
      for member <- members do
        ask = asks[member.id]
        %{member: member, ask: ask, reason: reason(member, ask, retiring_ids, scope)}
      end

    {send, left_out} = Enum.split_with(rows, &is_nil(&1.reason))
    %{send: Enum.map(send, &Map.delete(&1, :reason)), left_out: left_out}
  end

  defp reason(member, ask, retiring_ids, scope) do
    cond do
      member.not_a_person -> :not_a_person
      MapSet.member?(retiring_ids, member.id) -> :retiring
      scope == :everyone and member.has_photo -> :has_photo
      member.email in [nil, ""] -> :no_email
      scope == :everyone and ask != nil -> :asked
      true -> nil
    end
  end

  @doc """
  The plan for `scope` as the team stands now: `:everyone`, its counted, current
  members, or one `%Member{}`.
  """
  def load_plan(%Team{} = team, :everyone, now) do
    team
    |> Member.get_all_counted(now)
    |> plan(PhotoAsk.open_for_team(team), Standing.retiring_ids(team), :everyone)
  end

  def load_plan(%Team{id: team_id} = team, %Member{team_id: team_id} = member, _now) do
    asks = member |> PhotoAsk.open_for_member() |> List.wrap()
    plan([member], asks, Standing.retiring_ids(team), :one)
  end

  @doc """
  Asks everyone the plan for `scope` sends to, from `user`, with their `message` or
  none. `{:ok, asks}`, which is `[]` when there is nobody to ask, or
  `{:error, :message_too_long}`.
  """
  def call(%Team{} = team, %User{} = user, scope, message, now) do
    message = Message.normalize(message)

    if Message.fits?(message) do
      %{send: send} = load_plan(team, scope, now)
      {:ok, Enum.map(send, &ask(&1, team, user, message, now))}
    else
      {:error, :message_too_long}
    end
  end

  # The ask and its job commit together, or neither does.
  defp ask(%{member: member, ask: open}, team, user, message, now) do
    {:ok, ask} =
      Repo.transaction(fn ->
        ask =
          (open || %PhotoAsk{team_id: team.id, member_id: member.id})
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
  that closed, or whose member has no email now, is `{:cancel, reason}`. One already
  sent sends nothing, so a job that runs twice sends one email.
  """
  def deliver(ask_id, last?, now) do
    case PhotoAsk.get_open(ask_id) do
      nil -> {:cancel, "no open ask"}
      %PhotoAsk{email_status: :queued} = ask -> send_email(ask, last?, now)
      %PhotoAsk{} -> :ok
    end
  end

  defp send_email(%PhotoAsk{member: %Member{email: email}} = ask, _last?, _now)
       when email in [nil, ""] do
    PhotoAsk.set_email_status!(ask, :failed)
    {:cancel, "the member has no email"}
  end

  defp send_email(%PhotoAsk{member: member, team: team} = ask, last?, now) do
    url = Web.PhotoAskLinks.url(ask)
    clean_up? = CleanUpPhoto.available?()

    case PhotoAskMailer.deliver(member, team, asker(ask, now), ask.message, url, clean_up?) do
      {:ok, _sent} ->
        PhotoAsk.set_email_status!(ask, :sent)
        :ok

      {:error, error} ->
        if last?, do: PhotoAsk.set_email_status!(ask, :failed)
        {:error, error}
    end
  end

  @doc """
  Who asked, as `%{name:, email:}`: their member name on the team, or their email when
  no current member has it. Nil when their login is gone.
  """
  def asker(%PhotoAsk{asked_by_user: nil}, _now), do: nil

  def asker(%PhotoAsk{asked_by_user: user, team: %Team{} = team}, now),
    do: %{name: Member.name_for_user(team, user, now), email: user.email}

  @doc """
  The member's open ask as their pages show it, `%{ask:, asked_by:}` with who asked's
  name, or nil for none or with Photos off.
  """
  def open_for(%Team{} = team, %Member{} = member, now) do
    with true <- Team.photos?(team),
         %PhotoAsk{} = ask <- PhotoAsk.open_for_member(member) do
      asker = asker(%{ask | team: team}, now)
      %{ask: ask, asked_by: (asker && asker.name) || "A team admin"}
    else
      _none -> nil
    end
  end

  @doc "What a call/5 error says."
  def error_text(:message_too_long), do: Message.error_text()
end
