defmodule App.Model.ChangeSetRow do
  use App, :model

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # One D4H record in a change set. `old_value` is what D4H had when the row was proposed
  # and `new_value` what it gets, both with string keys. `d4h_record_id` is the attendance
  # row or group membership; a create fills it from D4H's answer. A row stays proposed
  # until it's applied, fails with D4H's error, or is skipped because D4H changed first.
  schema "change_set_rows" do
    belongs_to :change_set, ChangeSet
    belongs_to :team, Team
    belongs_to :member, Member

    field :action, Ecto.Enum,
      values: [
        :update_attendance,
        :create_attendance,
        :add_group_member,
        :remove_group_member,
        :create_member,
        :update_member,
        :retire_member,
        :rejoin_member,
        :set_member_photo,
        :remove_member_photo,
        :create_activity,
        :update_activity,
        :delete_activity,
        :create_qualification,
        :update_qualification,
        :delete_qualification,
        :award_qualification,
        :remove_award,
        :create_group,
        :update_group,
        :delete_group,
        :create_equipment_usage,
        :delete_equipment_usage
      ]

    field :d4h_record_id, :integer
    field :old_value, :map
    field :new_value, :map
    field :reason, :string
    field :status, Ecto.Enum, values: [:proposed, :applied, :failed, :skipped]
    field :error, :string
    field :applied_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Records how the write went: `{:applied, d4h_record_id}`, or `{status, error}`."
  def record!(%ChangeSetRow{} = row, {:applied, d4h_record_id}, now) do
    row
    |> change(status: :applied, d4h_record_id: d4h_record_id, error: nil, applied_at: now)
    |> Repo.update!()
  end

  def record!(%ChangeSetRow{} = row, {status, error}, _now) when status in [:failed, :skipped] do
    row |> change(status: status, error: error) |> Repo.update!()
  end

  @doc "Puts a row back to proposed."
  def reset!(%ChangeSetRow{} = row),
    do: row |> change(status: :proposed, error: nil) |> Repo.update!()
end
