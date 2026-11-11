defmodule App.Model.SignRequest do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.Member
  alias App.Model.SignRequest
  alias App.Model.Team
  alias App.Repo

  # A team admin asking a form's task leader to sign it (#993). The task leader gets it
  # in For you to do and by email, and signs on its page, which publishes the form. One
  # is open per form and activity until it ends. App.Operation.AskToSign asks and
  # cancels, and App.Operation.PublishDocument ends it when the form is signed.
  schema "sign_requests" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :form, Form
    # The task leader asked.
    belongs_to :member, Member
    # The team admin who asked, who gets the PDF when it's signed.
    belongs_to :asked_by, User
    # The PDF's title when asked, "Task report 26-06613".
    field :title, :string
    field :asked_at, :utc_datetime
    field :ended_at, :utc_datetime

    # Why it ended: the task leader signed, a team admin signed for them, cancelled it,
    # or asked again, or the Task Leader's Name no longer names them.
    field :ended_why, Ecto.Enum,
      values: [:signed, :signed_for, :cancelled, :replaced, :leader_changed]

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Whether the request is still open."
  def open?(%SignRequest{ended_at: ended_at}), do: is_nil(ended_at)

  @doc "The open request for `form` on `activity`, or nil, with who asked."
  def open_for(%Activity{id: activity_id}, %Form{id: form_id}) do
    SignRequest
    |> where([r], r.activity_id == ^activity_id and r.form_id == ^form_id)
    |> where([r], is_nil(r.ended_at))
    |> preload([:member, :asked_by])
    |> Repo.one()
  end

  @doc """
  The newest request to `member` for `form` on `activity`, open or ended, or nil: what
  the sign page shows them.
  """
  def latest_for(%Member{id: member_id}, %Activity{id: activity_id}, %Form{id: form_id}) do
    SignRequest
    |> where([r], r.member_id == ^member_id)
    |> where([r], r.activity_id == ^activity_id and r.form_id == ^form_id)
    |> order_by([r], desc: r.id)
    |> limit(1)
    |> preload([:asked_by])
    |> Repo.one()
  end

  @doc "The member's open requests, oldest first, each with its activity, form, and who asked."
  def open_for_member(%Member{id: member_id}) do
    SignRequest
    |> where([r], r.member_id == ^member_id and is_nil(r.ended_at))
    |> order_by([r], asc: r.asked_at, asc: r.id)
    |> preload([:activity, :form, :asked_by])
    |> Repo.all()
  end

  @doc """
  Ends the open request for `form_id` on `activity_id`, if there is one, `why` at `now`:
  `{:ok, request}` with the request it ended, or `{:ok, nil}`. Call it in the
  transaction that makes it end.
  """
  def end_open(activity_id, form_id, why, now) do
    ended =
      SignRequest
      |> where([r], r.activity_id == ^activity_id and r.form_id == ^form_id)
      |> where([r], is_nil(r.ended_at))
      |> select([r], r)
      |> Repo.update_all(
        set: [
          ended_at: DateTime.truncate(now, :second),
          ended_why: why,
          updated_at: DateTime.utc_now()
        ]
      )

    case ended do
      {_count, [request]} -> {:ok, request}
      {_count, []} -> {:ok, nil}
    end
  end
end
