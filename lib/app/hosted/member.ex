defmodule App.Hosted.Member do
  use App, :model

  @statuses ~w(OPERATIONAL NON_OPERATIONAL OBSERVER RETIRED)

  # D4H's access levels, which decide who manages the team in SAR Duty:
  # 0 OWNER, 1 EDITOR, 2 MEMBER, 3 MEMBER_PLUS, 4 NO_ACCESS.
  @permissions 0..4

  schema "hosted_members" do
    field :hosted_team_id, :integer
    field :ref, :string
    field :name, :string
    field :position, :string
    field :email, :string, redact: true
    field :phone, :string, redact: true
    field :address, :string, redact: true
    field :status, :string, default: "OPERATIONAL"
    field :permission, :integer, default: 2
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(member, attrs) do
    member
    |> cast(attrs, [
      :ref,
      :name,
      :position,
      :email,
      :phone,
      :address,
      :status,
      :permission,
      :starts_at,
      :ends_at
    ])
    |> validate_required([:name, :status, :permission, :starts_at])
    |> validate_length(:name, max: 100)
    |> validate_length(:ref, max: 100)
    |> validate_length(:position, max: 100)
    |> validate_length(:email, max: 250)
    |> validate_length(:phone, max: 100)
    |> validate_length(:address, max: 300)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:permission, @permissions)
  end
end
