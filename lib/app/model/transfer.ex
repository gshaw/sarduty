defmodule App.Model.Transfer do
  use App, :model

  alias App.Accounts.User
  alias App.Field.EncryptedString
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Model.Transfer
  alias App.Model.TransferAward
  alias App.Repo

  # A transfer (#892): a copy of a member's awards and their certificates, made by a team
  # admin at the member's old team, that a team admin at their new team adds with the
  # code. The awards are copied from the sending team's D4H when the code is made, so the
  # new team never reads it. The code works once, for 30 days, until used or cancelled;
  # then the copied files go.
  schema "transfers" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :made_by_user, User
    belongs_to :cancelled_by_user, User
    belongs_to :used_by_team, Team
    has_many :awards, TransferAward, preload_order: [asc: :position]
    # Stored without the dash, as MemberCard.generate_code/0 makes it. Encrypted so the
    # sending team's page can show it again; the hash finds it from what was typed.
    field :code, EncryptedString, redact: true
    field :code_hash, :string, redact: true
    # Who it is for, as the sending team had them when the code was made.
    field :member_name, :string, redact: true
    field :member_email, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @days_open 30

  @doc "How long a code works, in days."
  def days_open, do: @days_open

  @doc "When a code made at `now` stops working."
  def expires_at(%DateTime{} = now), do: DateTime.add(now, @days_open, :day)

  @doc "A new code, stored without the dash."
  def generate_code, do: MemberCard.generate_code()

  @doc "The code as people read and type it: `K7QM-4XRD`."
  def format_code(%Transfer{code: code}), do: MemberCard.format_code(code)

  @doc """
  The hash a code is found by, from what someone typed, or nil when it can't be a code.
  Case, spaces, and dashes don't matter.
  """
  def code_hash(input) do
    case MemberCard.normalize_code(input) do
      nil -> nil
      code -> :sha256 |> :crypto.hash(code) |> Base.encode16(case: :lower)
    end
  end

  @doc "`:open`, `:used`, `:cancelled`, or `:expired` at `now`."
  def status(%Transfer{used_at: %DateTime{}}, _now), do: :used
  def status(%Transfer{cancelled_at: %DateTime{}}, _now), do: :cancelled

  def status(%Transfer{expires_at: expires_at}, now),
    do: if(DateTime.after?(expires_at, now), do: :open, else: :expired)

  def open?(%Transfer{} = transfer, now), do: status(transfer, now) == :open

  @doc """
  The member's transfer by local id, with its awards and who made, cancelled, or used it.
  Looked up through the team and the member, never by the bare id; raises
  Ecto.NoResultsError, a 404, otherwise.
  """
  def find!(%Team{} = team, %Member{} = member, id) do
    Transfer
    |> where([t], t.id == ^id and t.team_id == ^team.id and t.member_id == ^member.id)
    |> preload([:awards, :made_by_user, :cancelled_by_user, :used_by_team])
    |> Repo.one!()
  end

  @doc """
  The member's code that still works at `now`, or nil. A member has at most one: making
  another waits until it is used, cancelled, or expired (MakeTransfer).
  """
  def open_for_member(%Member{} = member, now) do
    Transfer
    |> where([t], t.team_id == ^member.team_id and t.member_id == ^member.id)
    |> where([t], is_nil(t.used_at) and is_nil(t.cancelled_at) and t.expires_at > ^now)
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> limit(1)
    |> Repo.one()
  end
end
