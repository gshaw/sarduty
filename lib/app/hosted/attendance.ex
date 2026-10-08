defmodule App.Hosted.Attendance do
  use App, :model

  alias App.Hosted.Activity

  @statuses ~w(ATTENDING ABSENT REQUESTED)

  schema "hosted_attendances" do
    field :hosted_team_id, :integer
    field :activity_id, :integer
    field :member_id, :integer
    field :status, :string, default: "REQUESTED"
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    # The activity's kind, which the JSON names: Event, Exercise, or Incident.
    field :activity_kind, :string, virtual: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attendance, attrs) do
    attendance
    |> cast(attrs, [:status, :starts_at, :ends_at])
    |> validate_required([:status, :starts_at, :ends_at])
    |> validate_inclusion(:status, @statuses)
    |> Activity.validate_ends_after_starts()
  end

  @doc "Whole minutes from start to end, as D4H's `duration`."
  def duration(%__MODULE__{starts_at: starts_at, ends_at: ends_at}),
    do: div(DateTime.diff(ends_at, starts_at), 60)
end
