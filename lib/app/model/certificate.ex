defmodule App.Model.Certificate do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Model.ChangeSet
  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  # A member's certificate for a qualification (#493). It waits until a team admin
  # accepts it, which adds the award to D4H with the file on it, or declines it with a
  # reason the member sees. The dates are days on the team's clock. The file is a
  # CertificateFile, kept only while the certificate waits.
  schema "certificates" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :qualification, Qualification
    belongs_to :decided_by_user, User
    # The accept's change set, kept so Send again tries only its failed row.
    belongs_to :change_set, ChangeSet
    has_one :file, CertificateFile
    field :starts_on, :date
    field :ends_on, :date
    field :status, Ecto.Enum, values: [:waiting, :accepted, :declined], default: :waiting
    # The name the member's file had, for the team admin's page.
    field :file_name, :string
    field :content_type, :string
    field :file_size, :integer
    # The member's note for the team admin, such as which course it was.
    field :note, TrimmedString, redact: true
    field :decline_reason, TrimmedString, redact: true
    field :decided_at, :utc_datetime_usec
    # Set once the award is in D4H, even when its file is not yet.
    field :d4h_award_id, :integer
    field :d4h_document_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  What the member sends: the qualification if they know it, the dates, and a note.
  `qualification_ids` are the ones it may have: the team's.
  """
  def member_changeset(data, params, qualification_ids) do
    data
    |> cast(params, [:qualification_id, :starts_on, :ends_on, :note])
    |> validate_dates(qualification_ids)
    |> validate_length(:note, max: 300, message: "Keep the note under 300 characters")
    |> App.Validate.in_field_order([:qualification_id, :starts_on, :ends_on, :note])
  end

  @doc """
  What a team admin accepts: a qualification, the dates, and `confirmed`, the box they
  select once they have checked them against the certificate. Nothing keeps it.
  """
  def accept_changeset(data, params, qualification_ids) do
    data
    |> cast(params, [:qualification_id, :starts_on, :ends_on])
    |> validate_required([:qualification_id], message: "Select a qualification")
    |> validate_dates(qualification_ids)
    |> validate_acceptance(:confirmed, message: "Check the certificate, then select the box")
    |> App.Validate.in_field_order([:qualification_id, :starts_on, :ends_on, :confirmed])
  end

  defp validate_dates(changeset, qualification_ids) do
    changeset
    |> validate_required([:starts_on], message: "Enter the date on the certificate")
    |> validate_inclusion(:qualification_id, qualification_ids, message: "Select a qualification")
    |> validate_ends_after_start()
  end

  defp validate_ends_after_start(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && not Date.after?(ends_on, starts_on),
      do: add_error(changeset, :ends_on, "Enter an expiry after the start"),
      else: changeset
  end

  @doc "A team admin's decline, with a reason the member sees."
  def decline_changeset(%Certificate{} = certificate, reason, user, now) do
    certificate
    |> cast(%{decline_reason: reason}, [:decline_reason])
    |> change(status: :declined, decided_by_user_id: user.id, decided_at: now)
    |> validate_required([:decline_reason], message: "Enter why, for the member")
    |> validate_length(:decline_reason, max: 300, message: "Keep it under 300 characters")
  end

  @doc """
  When the award would expire, for a certificate starting `starts_on`: D4H's length for
  the qualification, or else the length of the member's last award of it. `{ends_on,
  months}`, or nil when neither says.
  """
  def default_ends_on(%Date{} = starts_on, %Qualification{} = qualification, last_award) do
    case months(qualification, last_award) do
      nil -> nil
      months -> {Date.shift(starts_on, month: months), months}
    end
  end

  def default_ends_on(_starts_on, _qualification, _last_award), do: nil

  defp months(%Qualification{expires_months_default: months}, _award)
       when is_integer(months) and months > 0,
       do: months

  defp months(_qualification, %{
         starts_at: %DateTime{} = starts_at,
         ends_at: %DateTime{} = ends_at
       }) do
    case Service.Convert.duration_to_months(starts_at, ends_at) do
      months when months > 0 -> months
      _none -> nil
    end
  end

  defp months(_qualification, _award), do: nil

  @doc """
  What looks wrong about the dates, for the team admin to check: never an error, since a
  certificate can be odd and still right. `:starts_after_today`, or the expiry against
  `default`, `default_ends_on/3`'s answer: `{:length, usual_months, months}` when they
  are over a month apart, or `{:no_expiry, usual_months}`.
  """
  def date_warnings(starts_on, ends_on, default, %Date{} = today) do
    after_today = if starts_on && Date.after?(starts_on, today), do: [:starts_after_today]
    (after_today || []) ++ length_warnings(starts_on, ends_on, default)
  end

  defp length_warnings(_starts_on, _ends_on, nil), do: []
  defp length_warnings(_starts_on, nil, {_usual_ends_on, months}), do: [{:no_expiry, months}]

  defp length_warnings(starts_on, ends_on, {usual_ends_on, months}) do
    if abs(Date.diff(ends_on, usual_ends_on)) > 31,
      do: [{:length, months, months_between(starts_on, ends_on)}],
      else: []
  end

  # Whole months from one date to the other, to the nearest.
  defp months_between(starts_on, ends_on) do
    months = (ends_on.year - starts_on.year) * 12 + ends_on.month - starts_on.month

    cond do
      ends_on.day - starts_on.day >= 15 -> months + 1
      ends_on.day - starts_on.day <= -15 -> months - 1
      true -> months
    end
  end

  @doc "Whether the award would be over already: it goes in as a past award."
  def expired_by?(nil, _today), do: false
  def expired_by?(%Date{} = ends_on, %Date{} = today), do: not Date.after?(ends_on, today)

  @doc "Whether the member can change it: while it waits and nothing is in D4H yet."
  def member_can_change?(%Certificate{status: status, d4h_award_id: award_id}),
    do: status == :waiting and is_nil(award_id)

  @doc "Whether the member can delete it: as they can change it, or once declined."
  def member_can_delete?(%Certificate{status: :declined}), do: true
  def member_can_delete?(%Certificate{} = certificate), do: member_can_change?(certificate)

  @doc "A team admin can change its qualification and dates until the award is in D4H."
  def dates_locked?(%Certificate{d4h_award_id: award_id}), do: not is_nil(award_id)

  @doc """
  The member's certificates for Your membership: waiting ones and declined ones they
  haven't deleted, newest first.
  """
  def get_open_for_member(%Member{} = member) do
    Certificate
    |> where([c], c.team_id == ^member.team_id and c.member_id == ^member.id)
    |> where([c], c.status in [:waiting, :declined])
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> preload(:qualification)
    |> Repo.all()
  end

  @doc """
  The team's certificates in `status`, with their members and qualifications: waiting
  ones oldest first, to accept in turn, and the rest newest first.
  """
  def get_all_for_team(team_id, status) do
    Certificate
    |> where([c], c.team_id == ^team_id and c.status == ^status)
    |> order_by_status(status)
    |> preload([:member, :qualification])
    |> Repo.all()
  end

  defp order_by_status(query, :waiting), do: order_by(query, [c], asc: c.inserted_at, asc: c.id)

  defp order_by_status(query, _status),
    do: order_by(query, [c], desc: c.decided_at, desc: c.id)

  @doc "How many of the team's certificates are in each status, with every status there."
  def count_by_status(team_id) do
    counts =
      Certificate
      |> where([c], c.team_id == ^team_id)
      |> group_by([c], c.status)
      |> select([c], {c.status, count(c.id)})
      |> Repo.all()
      |> Map.new()

    Map.merge(%{waiting: 0, accepted: 0, declined: 0}, counts)
  end

  @doc """
  Whether `member` sent it: a team admin's own certificate, which another team admin
  should accept (#697). Nil, a user who isn't one of the team's members, has none.
  """
  def own?(%Certificate{member_id: member_id}, %Member{id: member_id}), do: true
  def own?(%Certificate{}, _member), do: false

  @doc """
  How many of the team's waiting certificates ask for `member`, a team admin: all but
  their own, which another team admin should accept (#697). With no other team admin,
  their own count too, since nobody else will accept them. A nil member, a SAR Duty admin
  who isn't on the team, has none of their own.
  """
  def count_to_accept(%Team{} = team, member, now) do
    Certificate
    |> where([c], c.team_id == ^team.id and c.status == :waiting)
    |> without_own(member, Member.other_managers?(team, member, now))
    |> Repo.aggregate(:count)
  end

  defp without_own(query, %Member{id: id}, true), do: where(query, [c], c.member_id != ^id)
  defp without_own(query, _member, _other_managers?), do: query

  @doc "One of the team's certificates, with what its page shows."
  def find!(%Team{} = team, id) do
    Certificate
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload([:member, :qualification, :decided_by_user, change_set: :rows])
  end

  @doc "One of the member's own certificates."
  def find_for_member!(%Member{} = member, id) do
    Certificate
    |> Repo.get_by!(id: id, team_id: member.team_id, member_id: member.id)
    |> Repo.preload(:qualification)
  end
end
