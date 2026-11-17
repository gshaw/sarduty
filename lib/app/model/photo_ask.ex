defmodule App.Model.PhotoAsk do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.PhotoAsk
  alias App.Model.Team
  alias App.Repo

  # A team admin asking a member for a photo (#1030): who asked, when, and their message.
  # It is open until the member's photo is added, by them or a team admin, which sets
  # `closed_at`. A member has one open ask: asking again moves its date and sends another
  # email. `email_status` is how the last email went, for its job,
  # App.Worker.SendPhotoAskWorker.
  schema "photo_asks" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :asked_by_user, User
    # The team admin's own words, at the top of the email.
    field :message, :string, redact: true
    field :asked_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    field :email_status, Ecto.Enum, values: [:queued, :sent, :failed], default: :queued
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The member's open ask, with who asked, or nil."
  def open_for_member(%Member{} = member) do
    PhotoAsk
    |> where([a], a.team_id == ^member.team_id and a.member_id == ^member.id)
    |> where([a], is_nil(a.closed_at))
    |> preload(:asked_by_user)
    |> Repo.one()
  end

  @doc "The team's open asks."
  def open_for_team(%Team{} = team) do
    PhotoAsk
    |> where([a], a.team_id == ^team.id and is_nil(a.closed_at))
    |> Repo.all()
  end

  @doc """
  An open ask with its team, member, and who asked, or nil once it closes or is gone.
  The member is found through the ask's team.
  """
  def get_open(id) do
    PhotoAsk
    |> join(:inner, [a], t in assoc(a, :team))
    |> join(:inner, [a, t], m in assoc(a, :member), on: m.team_id == t.id)
    |> where([a], a.id == ^id and is_nil(a.closed_at))
    |> preload([a, t, m], [:asked_by_user, team: t, member: m])
    |> Repo.one()
  end

  @doc "Closes the member's open ask, if they have one: their photo was added."
  def close_for_member(%Member{} = member, now) do
    PhotoAsk
    |> where([a], a.team_id == ^member.team_id and a.member_id == ^member.id)
    |> where([a], is_nil(a.closed_at))
    |> Repo.update_all(set: [closed_at: now, updated_at: now])

    :ok
  end

  @doc "Stores how the ask's email went."
  def set_email_status!(%PhotoAsk{} = ask, status),
    do: ask |> change(email_status: status) |> Repo.update!()
end
