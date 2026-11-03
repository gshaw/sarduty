defmodule App.Model.Trip do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Member
  alias App.Model.Team
  alias App.Model.Trip
  alias App.Repo

  # How one attended row got to its activity, and the km it counts (#230): drove to the
  # ICP (the activity's location) or to the yard, a passenger (0 km), or km a person
  # typed. `km` is saved when it's set, so a later change to a home or a route never
  # moves it. Keyed by D4H's attendance id, which outlives the local row. SAR Duty's own
  # data: the km reach D4H only by hand, and a published activity's trips can't change.
  schema "trips" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :set_by_user, User
    field :d4h_attendance_id, :integer
    field :travel, :string
    field :km, :integer
    # When the member said it's right or changed it (#230), or nil. A team admin's set
    # clears it, unless the row is the admin's own.
    field :checked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @travels ~w(icp yard passenger other)

  @doc "Marks the member's trip checked: they said it's right."
  def check!(%Trip{} = trip, now),
    do:
      trip |> Ecto.Changeset.change(checked_at: DateTime.truncate(now, :second)) |> Repo.update!()

  @doc """
  The member's trips on one activity, by D4H attendance id, with who set each.
  """
  def for_member(%Activity{} = activity, %Member{} = member) do
    query =
      from(t in Trip,
        where:
          t.team_id == ^member.team_id and t.activity_id == ^activity.id and
            t.member_id == ^member.id,
        preload: :set_by_user
      )

    query
    |> Repo.all()
    |> Map.new(&{&1.d4h_attendance_id, &1})
  end

  @doc """
  The member's trips they haven't checked, on activities still open to change: neither
  published nor deleted. Each with its activity, oldest activity first.
  """
  def unchecked_for_member(%Member{} = member) do
    query =
      from(t in Trip,
        join: a in assoc(t, :activity),
        where:
          t.team_id == ^member.team_id and t.member_id == ^member.id and is_nil(t.checked_at) and
            a.team_id == ^member.team_id and (a.is_published == false or is_nil(a.is_published)) and
            is_nil(a.deleted_at),
        order_by: [asc: a.started_at, asc: t.id],
        preload: [activity: a]
      )

    Repo.all(query)
  end

  @doc "Each way a row can be set: icp, yard, passenger, other."
  def travels, do: @travels

  @doc "The activity's trips, by D4H attendance id."
  def by_attendance(%Activity{} = activity) do
    query =
      from(t in Trip, where: t.team_id == ^activity.team_id and t.activity_id == ^activity.id)

    query
    |> Repo.all()
    |> Map.new(&{&1.d4h_attendance_id, &1})
  end

  @doc "Takes these rows' trips away, by D4H attendance id: back to not set."
  def delete_all!(%Activity{}, []), do: :ok

  def delete_all!(%Activity{} = activity, d4h_attendance_ids) do
    query =
      from(t in Trip,
        where:
          t.team_id == ^activity.team_id and t.activity_id == ^activity.id and
            t.d4h_attendance_id in ^d4h_attendance_ids
      )

    Repo.delete_all(query)
    :ok
  end

  @doc """
  Saves each `%{attendance: row, travel: travel, km: km}`, replacing a row's trip if it
  has one. One insert. `checked_member_id` is the member whose rows count as checked:
  the member setting their own, or the team admin's own rows. Nil for none.
  """
  def save_all!(%Activity{} = activity, user, sets, now, checked_member_id \\ nil) do
    now = DateTime.truncate(now, :second)

    rows =
      for %{attendance: row, travel: travel, km: km} <- sets, travel in @travels do
        %{
          team_id: activity.team_id,
          activity_id: activity.id,
          member_id: row.member_id,
          d4h_attendance_id: row.d4h_attendance_id,
          travel: travel,
          km: km,
          set_by_user_id: user && user.id,
          checked_at: if(row.member_id == checked_member_id, do: now),
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Trip, rows,
      on_conflict: {:replace, [:travel, :km, :set_by_user_id, :checked_at, :updated_at]},
      conflict_target: [:activity_id, :d4h_attendance_id]
    )
  end
end
