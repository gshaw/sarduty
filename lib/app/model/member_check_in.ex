defmodule App.Model.MemberCheckIn do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Member
  alias App.Model.MemberCheckIn
  alias App.Model.Team
  alias App.Repo

  # A team admin reached a member and wrote down what they heard (#366). It restarts the
  # member's attendance clock. That is all: not standing, not groups, nothing in D4H.
  # Members don't see it.
  schema "member_check_ins" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :user, User
    field :checked_in_on, :date
    field :note, TrimmedString, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def build_changeset(data, params, %Date{} = today) do
    data
    |> cast(params, [:checked_in_on, :note])
    |> validate_required([:checked_in_on], message: "Enter the day you reached the member.")
    |> validate_length(:note, max: 500, message: "Keep the note under 500 characters.")
    |> validate_not_after(:checked_in_on, today)
    |> App.Validate.in_field_order([:checked_in_on, :note])
  end

  defp validate_not_after(changeset, field, today) do
    case get_field(changeset, field) do
      %Date{} = date ->
        if Date.after?(date, today),
          do: add_error(changeset, field, "Enter today or an earlier day."),
          else: changeset

      _none ->
        changeset
    end
  end

  @doc "The member's check-ins, latest first, with who recorded each."
  def for_member(%Member{} = member) do
    MemberCheckIn
    |> where([c], c.team_id == ^member.team_id and c.member_id == ^member.id)
    |> order_by([c], desc: c.checked_in_on, desc: c.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Each of the team's members' latest check-in, as rows of `member_id` and
  `checked_in_on`. Members never checked in have no row.
  """
  def latest_query(%Team{} = team) do
    from c in MemberCheckIn,
      where: c.team_id == ^team.id,
      group_by: c.member_id,
      select: %{member_id: c.member_id, checked_in_on: max(c.checked_in_on)}
  end
end
