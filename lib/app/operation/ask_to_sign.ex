defmodule App.Operation.AskToSign do
  @moduledoc """
  A team admin asks a form's task leader to sign it (#993), from the preview Publish
  opens: the task leader gets an item in For you to do and an email with a link to the
  sign page, where Sign and publish publishes the form signed in their name
  (App.Operation.PublishDocument.publish_asked/5). The task leader needn't be a team
  admin, but must be able to log in: they have an email, and they're a team admin or
  member logins let them in.

  One request is open per form and activity (App.Model.SignRequest). Asking again ends
  the last one and emails again. A request ends when the task leader signs, a team admin
  cancels it or signs for them, or the Task Leader's Name no longer names them.
  """

  alias App.Model.Member
  alias App.Model.SignRequest
  alias App.Model.Team
  alias App.Operation.PublishDocument
  alias App.Operation.SignForm
  alias App.Repo
  alias App.Worker.EmailSignRequestWorker

  @doc """
  Asks the task leader the preview from `PublishDocument.preview/5` signs for:
  `{:ok, request}` or `{:error, message}`. Checks again that `user` may publish, and
  that the task leader is the one the preview named.
  """
  def call(%Team{} = team, form, activity, user, preview, now \\ DateTime.utc_now()) do
    signed = preview.printed.signed

    with :ok <- PublishDocument.check(team, form, activity, user, now),
         :ok <- PublishDocument.same_leader(team, form, activity, preview, now),
         :ok <- can_ask(signed, team, now) do
      ask(
        %SignRequest{
          team_id: team.id,
          activity_id: activity.id,
          form_id: form.id,
          member_id: signed.leader.id,
          asked_by_id: user.id,
          title: preview.printed.attachment.title,
          asked_at: DateTime.truncate(now, :second)
        },
        now
      )
    end
  end

  defp can_ask(signed, team, now) do
    case askable(signed, team, now) do
      :ok -> :ok
      :none -> {:error, "There's no one to ask. Sign it yourself."}
      {:error, message} -> {:error, message}
    end
  end

  # The last request ends, then the new one and its email, in one transaction.
  defp ask(request, now) do
    Repo.transaction(fn ->
      {:ok, _ended} = SignRequest.end_open(request.activity_id, request.form_id, :replaced, now)
      request = Repo.insert!(request)
      EmailSignRequestWorker.enqueue_ask(request)
      request
    end)
  end

  @doc """
  Whether a team admin may ask the task leader of a preview's signing (App.Operation.
  SignForm's) to sign: `:ok`, `{:error, message}` saying why they can't, or `:none` when
  there's nobody to ask, since the task leader is signing or no one member has the name.
  """
  def askable(%{signed_for: whom, leader: %Member{} = leader}, %Team{} = team, now)
      when is_binary(whom) do
    cond do
      not SignForm.tells_leader?(%{signed_for: whom, leader: leader}) ->
        {:error, "#{leader.name} has no email, so they cannot log in to sign it."}

      Team.managed_by?(team, leader.email, now) ->
        :ok

      not team.member_logins ->
        {:error, "Member logins are off, so #{leader.name} cannot log in to sign it."}

      Member.get_login(leader.email, leader.id, now) == nil ->
        {:error,
         "#{leader.name} shares an email with another member, so they cannot log in to sign it."}

      true ->
        :ok
    end
  end

  def askable(_signed, _team, _now), do: :none

  @doc """
  Cancels the form's open request on the team: `{:ok, request}` or `{:error, message}`.
  Only a team admin cancels.
  """
  def cancel(%Team{} = team, %SignRequest{} = request, user, now \\ DateTime.utc_now()) do
    cond do
      request.team_id != team.id ->
        {:error, "This request is not on your team."}

      not PublishDocument.team_admin?(team, user, now) ->
        {:error, "Only a team admin can cancel a request."}

      not SignRequest.open?(request) ->
        {:error, "This request has ended."}

      true ->
        SignRequest.end_open(request.activity_id, request.form_id, :cancelled, now)
    end
  end

  @doc """
  Pure. Whether open `request` no longer asks the task leader: `found` is who the Task
  Leader's Name names now, App.Operation.SignForm.leader/4's, and it isn't the one member
  asked.
  """
  def leader_changed?(%SignRequest{member_id: id}, %{members: [%Member{id: id}]}), do: false
  def leader_changed?(%SignRequest{}, _found), do: true

  @doc """
  `request` while it still asks the form's task leader, or nil once it ends: one the
  Task Leader's Name no longer names ends now. `found` is who it names now.
  """
  def check_leader(nil, _found, _now), do: nil

  def check_leader(%SignRequest{} = request, found, now) do
    if SignRequest.open?(request) and leader_changed?(request, found) do
      {:ok, _ended} =
        SignRequest.end_open(request.activity_id, request.form_id, :leader_changed, now)

      nil
    else
      request
    end
  end

  @doc """
  `request` while it still asks the form's task leader, or nil, reading who the Task
  Leader's Name names now. Its team, activity, and form are loaded.
  """
  def current(%SignRequest{} = request, now) do
    %{team: team, activity: activity, form: form} = request

    case PublishDocument.leader_name(team, form, activity, now) do
      {:ok, name} -> check_leader(request, SignForm.leader(name, team, now), now)
      {:error, _message} -> request
    end
  end
end
