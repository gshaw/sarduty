defmodule App.Model.MemberPhoto do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Model.Team
  alias App.Repo

  # A photo a member added of themselves (#1029). It waits until a team admin accepts
  # it, which makes it the member's photo (SetMemberPhoto), or declines it with a reason
  # the member sees. While it waits the row keeps where the member placed it: `turns`,
  # quarter turns clockwise, and the square `x`, `y`, `side`, as Service.MemberPhoto
  # reads them. The photo as taken is a MemberPhotoFile, `width` × `height`, kept only
  # while the photo waits. The row stays, with who decided, when, and why.
  #
  # With Clean up (#1031) the file keeps the cleaned-up photo too, `cleaned_width` ×
  # `cleaned_height`, and `clean_up` is whether the Clean up switch was on: on, the
  # square is placed on the cleaned-up photo, and off, on the photo as taken.
  @reasons [
    sunglasses: "Sunglasses",
    hat: "Hat or helmet",
    dark: "Too dark",
    someone_else: "Someone else in it",
    busy_background: "Busy background",
    not_you: "Not a photo of you",
    something_else: "Something else"
  ]

  schema "member_photos" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :decided_by_user, User
    has_one :file, MemberPhotoFile
    field :status, Ecto.Enum, values: [:waiting, :accepted, :declined], default: :waiting
    field :width, :integer
    field :height, :integer
    field :turns, :integer, default: 0
    field :x, :float, default: 0.5
    field :y, :float, default: 0.5
    field :side, :float, default: 1.0
    field :clean_up, :boolean, default: false
    field :cleaned_width, :integer
    field :cleaned_height, :integer
    field :decline_reason, Ecto.Enum, values: Keyword.keys(@reasons), redact: true
    # The team admin's own words for the member, under the reason.
    field :decline_message, TrimmedString, redact: true
    field :decided_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Why a team admin declines a photo, in the order the check page lists them:
  `{key, text}`. While Clean up is available it removes any background, so Busy
  background is not one of them (#1031).
  """
  def reasons(clean_up_available?) when is_boolean(clean_up_available?) do
    if clean_up_available?, do: Keyword.delete(@reasons, :busy_background), else: @reasons
  end

  @doc ~s(A decline reason as people read it: "Too dark".)
  def reason_text(reason), do: Keyword.fetch!(@reasons, reason)

  @doc "Where the photo is placed, as Service.MemberPhoto.placement/1 gives it."
  def placed(%MemberPhoto{turns: turns, x: x, y: y, side: side}),
    do: {turns, %{x: x, y: y, side: side}}

  @doc "Whether the photo has a cleaned-up copy: Clean up answered when it was added."
  def cleaned?(%MemberPhoto{cleaned_width: width}), do: is_integer(width)

  @doc """
  Which of the photo's two files the square is placed on with the Clean up switch at
  `clean_up?`: `:cleaned`, or `:taken` with the switch off or no cleaned-up copy.
  """
  def shape(%MemberPhoto{} = photo, clean_up?),
    do: if(clean_up? and cleaned?(photo), do: :cleaned, else: :taken)

  @doc "The `{width, height}` of one of the photo's files, `:taken` or `:cleaned`."
  def size(%MemberPhoto{width: width, height: height}, :taken), do: {width, height}

  def size(%MemberPhoto{cleaned_width: width, cleaned_height: height}, :cleaned),
    do: {width, height}

  @doc """
  A team admin's decline: `reason`, one of `reasons/0` as the form sends it, and
  `message`, their own words for the member, or nil.
  """
  def decline_changeset(%MemberPhoto{} = photo, reason, message, %User{} = user, now) do
    photo
    |> cast(%{decline_message: message}, [:decline_message])
    |> change(
      status: :declined,
      decline_reason: reason(reason),
      decided_by_user_id: user.id,
      decided_at: now
    )
    |> validate_required([:decline_reason], message: "Select why not.")
    |> validate_length(:decline_message, max: 300, message: "Keep it under 300 characters.")
  end

  # The reason the form named, or nil for none or one that is not on the list.
  defp reason(text) do
    Enum.find_value(@reasons, fn {key, _text} -> if Atom.to_string(key) == text, do: key end)
  end

  @doc """
  Runs `fun` while nothing else changes the member's waiting photo: the member adding
  another, an accept, or a decline. An accept holds it while the photo is sent. Take it
  before a transaction, never inside one, as SaveCertificate.locked/2 says.
  """
  def locked(member_id, fun) when is_integer(member_id),
    do: :global.trans({{MemberPhoto, member_id}, self()}, fun)

  @doc "The member's photo that waits for a team admin, or nil. A member has at most one."
  def waiting_for_member(%Member{} = member) do
    MemberPhoto
    |> where([p], p.team_id == ^member.team_id and p.member_id == ^member.id)
    |> where([p], p.status == :waiting)
    |> order_by([p], desc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  The member's declined photo they have yet to answer, or nil: the last one they added,
  when a team admin declined it and nobody has set their photo since. Adding another
  answers it, and so does a team admin's own Add a photo.
  """
  def declined_for_member(%Member{} = member) do
    latest =
      MemberPhoto
      |> where([p], p.team_id == ^member.team_id and p.member_id == ^member.id)
      |> order_by([p], desc: p.id)
      |> limit(1)
      |> Repo.one()

    if latest && unanswered?(latest, member.photo_changed_at), do: latest
  end

  @doc """
  Pure. Whether a member's last photo is a decline they have yet to answer:
  `photo_changed_at` is when SAR Duty last set their photo, or nil.
  """
  def unanswered?(%MemberPhoto{status: :declined}, nil), do: true

  def unanswered?(%MemberPhoto{status: :declined, decided_at: decided_at}, changed_at),
    do: DateTime.before?(changed_at, decided_at)

  def unanswered?(%MemberPhoto{}, _changed_at), do: false

  @doc """
  The team's photos waiting for a team admin, oldest first, each with its member: Photos'
  Waiting view, and the count Needs attention shows. Only a counted, current member's,
  as Photos lists members, so a retiring member's does not count.
  """
  def get_waiting(%Team{} = team, now), do: team |> waiting_query(now) |> Repo.all()

  @doc "How many `get_waiting/2` lists."
  def count_waiting(%Team{} = team, now),
    do: team |> waiting_query(now) |> exclude(:preload) |> Repo.aggregate(:count)

  defp waiting_query(%Team{id: team_id}, now) do
    members =
      Member
      |> where([m], m.team_id == ^team_id)
      |> Member.counted_query()
      |> Member.current_query(now)
      |> select([m], m.id)

    MemberPhoto
    |> where([p], p.team_id == ^team_id and p.status == :waiting)
    |> where([p], p.member_id in subquery(members))
    |> order_by([p], asc: p.inserted_at, asc: p.id)
    |> preload(:member)
  end

  @doc "One of the team's photos, with its member and who decided it."
  def find!(%Team{} = team, id) do
    MemberPhoto
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload([:member, :decided_by_user])
  end

  @doc "One of the member's own photos."
  def find_for_member!(%Member{} = member, id),
    do: Repo.get_by!(MemberPhoto, id: id, team_id: member.team_id, member_id: member.id)
end
