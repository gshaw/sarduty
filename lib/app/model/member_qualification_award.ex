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
    # Its certificate in D4H (#314), set by RefreshD4HData.UpsertAwardDocuments.
    field :d4h_document_id, :integer
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
  @doc """
  `{member_id, d4h_qualification_id}` for each award a current member of the team holds
  at `now`.
  """
  def get_all_active_for_team(team_id, now) do
    MemberQualificationAward
    |> join(:inner, [a], q in assoc(a, :qualification), as: :qualification)
    |> join(:inner, [a], m in assoc(a, :member), as: :member)
    |> where([qualification: q, member: m], q.team_id == ^team_id and m.team_id == ^team_id)
    |> active_only(now)
    |> current_members_only(now)
    |> select([a, qualification: q], {a.member_id, q.d4h_qualification_id})
    |> Repo.all()
  end

  defp active_only(query, now), do: where(query, ^active_dynamic(now))

  @doc "active?/2 in SQL, on the query's first binding."
  def active_dynamic(now),
    do:
      dynamic(
        [a],
        (is_nil(a.starts_at) or a.starts_at <= ^now) and (is_nil(a.ends_at) or a.ends_at > ^now)
      )

  defp current_members_only(query, now),
    do: where(query, ^Member.current_dynamic(now, :member))

  def active?(%{starts_at: starts_at, ends_at: ends_at}, now) do
    (is_nil(starts_at) or not DateTime.after?(starts_at, now)) and
      (is_nil(ends_at) or DateTime.after?(ends_at, now))
  end

  def expired?(%{ends_at: ends_at}, now),
    do: not is_nil(ends_at) and not DateTime.after?(ends_at, now)

  @doc """
  A qualification's awards as its members, `{active, expired}`, one award each: a member
  with a current award is active, else one whose award ended is expired. A member whose
  only award hasn't started is in neither. Give each member's awards newest first; the
  first one kept is the one returned, in the order given.
  """
  def split_by_member(awards, now) do
    active = awards |> Enum.filter(&active?(&1, now)) |> Enum.uniq_by(& &1.member_id)
    active_ids = MapSet.new(active, & &1.member_id)

    expired =
      awards
      |> Enum.filter(&(expired?(&1, now) and not MapSet.member?(active_ids, &1.member_id)))
      |> Enum.uniq_by(& &1.member_id)

    {active, expired}
  end

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
      member: m,
      member_id: m.id,
      member_name: m.name,
      qualification_id: q.id,
      qualification: q.title,
      ends_at: max(aw.ends_at),
      award_id: max(aw.id)
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
    |> join(:inner, [aw], m in assoc(aw, :member), as: :member)
    |> join(:inner, [aw], q in assoc(aw, :qualification))
    |> where([_, m, q], m.team_id == ^team_id and q.team_id == ^team_id)
    |> where(^Member.current_dynamic(now, :member))
  end

  # SQLite hands back max() of a datetime column as text.
  defp to_datetime(%DateTime{} = datetime), do: datetime
  defp to_datetime(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")

  defp to_datetime(text) when is_binary(text) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(text)
    datetime
  end

  def get_by(params), do: Repo.get_by(MemberQualificationAward, params)

  @doc "How many members hold the qualification, for the warning before deleting it."
  def holder_count(%Qualification{} = qualification) do
    MemberQualificationAward
    |> where([a], a.qualification_id == ^qualification.id)
    |> join(:inner, [a], m in assoc(a, :member))
    |> where([a, m], m.team_id == ^qualification.team_id)
    |> select([a], count(a.member_id, :distinct))
    |> Repo.one()
  end

  @doc """
  The member's latest award of each qualification they hold or held, by qualification
  id: what a certificate's page compares with and fills its expiry from.
  """
  def latest_by_qualification(member_id) do
    MemberQualificationAward
    |> where(member_id: ^member_id)
    |> order_by([a], asc_nulls_first: a.starts_at, asc: a.id)
    |> Repo.all()
    |> Map.new(&{&1.qualification_id, &1})
  end

  @doc """
  The member's award with a certificate, by local id, with its qualification. Raises
  Ecto.NoResultsError, a 404, otherwise. Looked up through the member and their team,
  never by the bare id.
  """
  def find_certificate!(%Member{} = member, id) do
    MemberQualificationAward
    |> join(:inner, [a], q in assoc(a, :qualification))
    |> where([a, q], a.id == ^id and a.member_id == ^member.id and q.team_id == ^member.team_id)
    |> where([a], not is_nil(a.d4h_document_id))
    |> preload([a, q], qualification: q)
    |> Repo.one!()
  end

  @doc "Every award of the team's members, as `{id, d4h_award_id, d4h_document_id}`."
  def document_ids(team_id) do
    MemberQualificationAward
    |> join(:inner, [a], m in assoc(a, :member))
    |> join(:inner, [a], q in assoc(a, :qualification))
    |> where([a, m, q], m.team_id == ^team_id and q.team_id == ^team_id)
    |> select([a], {a.id, a.d4h_award_id, a.d4h_document_id})
    |> Repo.all()
  end

  @doc "Sets the certificate on awards by local id: `[{id, d4h_document_id or nil}]`."
  def set_documents(changes) do
    Enum.each(changes, fn {id, document_id} ->
      MemberQualificationAward
      |> where(id: ^id)
      |> Repo.update_all(set: [d4h_document_id: document_id])
    end)
  end

  def insert!(params) do
    changeset = MemberQualificationAward.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%MemberQualificationAward{} = record, params) do
    changeset = MemberQualificationAward.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
