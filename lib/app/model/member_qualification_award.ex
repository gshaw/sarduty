defmodule App.Model.MemberQualificationAward do
  use App, :model

  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo

  schema "member_qualification_awards" do
    belongs_to :member, Member
    belongs_to :qualification, Qualification
    field :d4h_award_id, :integer
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%MemberQualificationAward{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :member_id,
      :qualification_id,
      :d4h_award_id,
      :starts_at,
      :ends_at
    ])
    |> validate_required([
      :member_id,
      :qualification_id,
      :d4h_award_id
    ])
  end

  # The one definition of a current award, used by group rules and every page that
  # shows awards. Takes any map with starts_at and ends_at; either may be nil.
  def active?(%{starts_at: starts_at, ends_at: ends_at}, now) do
    (is_nil(starts_at) or not DateTime.after?(starts_at, now)) and
      (is_nil(ends_at) or DateTime.after?(ends_at, now))
  end

  def expired?(%{ends_at: ends_at}, now),
    do: not is_nil(ends_at) and not DateTime.after?(ends_at, now)

  @doc """
  Each current member's latest award of a qualification, when it ends between `now` and
  `until`, soonest first. A renewal pushes the latest end past `until`, and an award with
  no end never expires, so either takes the member off the list.
  """
  def expiring(team_id, now, until) do
    # Whole seconds, as stored, so text comparisons in SQLite line up.
    now = DateTime.truncate(now, :second)
    until = DateTime.truncate(until, :second)

    team_id
    |> current_members_awards(now)
    |> latest_ending_between(now, until)
    |> select_soonest_first()
    |> Repo.all()
    |> Enum.map(&Map.update!(&1, :ends_at, fn ends_at -> to_datetime(ends_at) end))
  end

  defp select_soonest_first(query) do
    query
    |> select([aw, m, q], %{
      member_id: m.id,
      member_name: m.name,
      qualification_id: q.id,
      qualification: q.title,
      ends_at: max(aw.ends_at)
    })
    |> order_by([aw, m], asc: max(aw.ends_at), asc: m.name)
  end

  defp latest_ending_between(query, now, until) do
    query
    |> group_by([aw, m, q], [m.id, q.id])
    |> having([aw], fragment("count(?) = count(?)", aw.id, aw.ends_at))
    |> having([aw], max(aw.ends_at) >= ^now and max(aw.ends_at) < ^until)
  end

  defp current_members_awards(team_id, now) do
    MemberQualificationAward
    |> join(:inner, [aw], m in assoc(aw, :member))
    |> join(:inner, [aw], q in assoc(aw, :qualification))
    |> where([_, m, q], m.team_id == ^team_id and q.team_id == ^team_id)
    |> where([_, m], is_nil(m.left_at) or m.left_at > ^now)
    |> where([_, m], is_nil(m.d4h_status) or m.d4h_status != "RETIRED")
  end

  # SQLite hands back max() of a datetime column as text.
  defp to_datetime(%DateTime{} = datetime), do: datetime
  defp to_datetime(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")

  defp to_datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> datetime
      _no_zone -> text |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    end
  end

  def get_by(params), do: Repo.get_by(MemberQualificationAward, params)

  def insert!(params) do
    changeset = MemberQualificationAward.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%MemberQualificationAward{} = record, params) do
    changeset = MemberQualificationAward.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
