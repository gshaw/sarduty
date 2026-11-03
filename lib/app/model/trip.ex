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
    timestamps(type: :utc_datetime)
  end

  @travels ~w(icp yard passenger other)

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

  @doc """
  Saves each `%{attendance: row, travel: travel, km: km}`, replacing a row's trip if it
  has one. One transaction.
  """
  def save_all!(%Activity{} = activity, user, sets, now) do
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
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Trip, rows,
      on_conflict: {:replace, [:travel, :km, :set_by_user_id, :updated_at]},
      conflict_target: [:activity_id, :d4h_attendance_id]
    )
  end
end
