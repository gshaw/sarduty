defmodule App.Model.D4HChange do
  use App, :model

  alias App.Model.Activity
  alias App.Model.D4HChange
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  # One change the D4H sync saw: a record added, changed, or removed in D4H between two
  # refreshes (#174, step 3). App.Operation.RecordD4HChanges writes them. `fields` names
  # what changed. `old_value` and `new_value` hold those fields with string keys, except
  # contact details, which are named in `fields` and never stored. D4H doesn't say who
  # made a change, so these never name a person.
  schema "d4h_changes" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :activity, Activity
    belongs_to :qualification, Qualification
    belongs_to :group, Group

    field :record_kind, Ecto.Enum,
      values: [:member, :activity, :attendance, :award, :group_membership]

    field :action, Ecto.Enum, values: [:added, :changed, :removed]
    field :d4h_record_id, :integer
    field :label, :string
    field :fields, {:array, :string}, default: []
    field :old_value, :map
    field :new_value, :map
    field :seen_after, :utc_datetime_usec
    field :seen_at, :utc_datetime_usec
  end

  # Attendance and awards are a record people come back to for years: letters, audits,
  # and group rules rely on them. The rest goes after 2 years.
  @kept_for_good [:attendance, :award]
  @retention_days 730

  def insert!(%D4HChange{} = change), do: Repo.insert!(change)

  @doc "A member's changes, newest first. Scoped to the team."
  def for_member(team_id, member_id, limit) do
    D4HChange
    |> where([c], c.team_id == ^team_id and c.member_id == ^member_id)
    |> newest_first(limit)
    |> preload(:activity)
    |> Repo.all()
  end

  @doc "An activity's changes, its own and its attendance, newest first."
  def for_activity(team_id, activity_id, limit) do
    D4HChange
    |> where([c], c.team_id == ^team_id and c.activity_id == ^activity_id)
    |> newest_first(limit)
    |> preload(:member)
    |> Repo.all()
  end

  defp newest_first(query, limit) do
    query |> order_by([c], desc: c.seen_at, desc: c.id) |> limit(^limit)
  end

  @doc "Deletes changes past retention. Returns how many."
  def prune(now) do
    cutoff = DateTime.add(now, -@retention_days, :day)

    {count, _} =
      D4HChange
      |> where([c], c.record_kind not in ^@kept_for_good and c.seen_at < ^cutoff)
      |> Repo.delete_all()

    count
  end
end
