defmodule App.Model.AttendanceScan do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.AttendanceScan
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # A member arriving at or leaving an activity, recorded on the Take attendance page from
  # their ID card (`method` "card") or picked by name ("name"). `recorded_by_user` took
  # it, and `recorded_by_member` is that user's member on the team, when they log in as
  # one; scans from attendance links before #475 have neither. Scans stay in SAR Duty
  # until a team admin sends the attendance to D4H.
  schema "attendance_scans" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :member, Member
    belongs_to :recorded_by_user, User
    belongs_to :recorded_by_member, Member
    field :kind, :string
    field :method, :string
    field :scanned_at, :utc_datetime_usec
    field :override_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: ["arrived", "left"]

  @doc "The time the scan stands for: the time typed in the time box, or when it happened."
  def time(%AttendanceScan{override_at: nil, scanned_at: scanned_at}), do: scanned_at
  def time(%AttendanceScan{override_at: override_at}), do: override_at

  def insert!(%AttendanceScan{kind: kind} = scan) when kind in ["arrived", "left"] do
    scan = Repo.insert!(scan)
    broadcast(scan.activity_id)
    scan
  end

  @doc "Deletes one of the activity's scans. A scan id from another activity does nothing."
  def delete(%Activity{} = activity, scan_id) do
    {count, _} =
      AttendanceScan
      |> where([s], s.id == ^scan_id and s.activity_id == ^activity.id)
      |> where([s], s.team_id == ^activity.team_id)
      |> Repo.delete_all()

    if count > 0, do: broadcast(activity.id)
    count
  end

  @doc "The activity's scans, oldest first, with their members and who recorded them."
  def get_all(%Activity{} = activity) do
    AttendanceScan
    |> where([s], s.activity_id == ^activity.id and s.team_id == ^activity.team_id)
    |> join(:inner, [s], m in assoc(s, :member))
    |> where([s, m], m.team_id == ^activity.team_id)
    |> order_by([s], asc: s.scanned_at, asc: s.id)
    |> preload([:member, :recorded_by_user, :recorded_by_member])
    |> Repo.all()
  end

  @doc "The topic a page listens on to hear about an activity's scans."
  def topic(activity_id), do: "attendance_scans:#{activity_id}"

  defp broadcast(activity_id),
    do: Phoenix.PubSub.broadcast(App.PubSub, topic(activity_id), :attendance_scans_changed)
end
