defmodule App.ViewModel.MemberFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.Member
  alias App.Validate

  @statuses [
    {"Operational", "OPERATIONAL"},
    {"Not operational", "NON_OPERATIONAL"},
    {"Observer", "OBSERVER"}
  ]

  # Adding or changing a hosted team's member. A team admin is a D4H Owner; anyone
  # else is a Member.
  @primary_key false
  embedded_schema do
    field :name, Field.TrimmedString
    field :ref_id, Field.TrimmedString
    field :position, Field.TrimmedString
    field :email, Field.TrimmedString
    field :phone, Field.TrimmedString
    field :address, Field.TrimmedString
    field :status, :string, default: "OPERATIONAL"
    field :team_admin, :boolean, default: false
    field :joined_on, :date
  end

  @fields [:name, :ref_id, :position, :email, :phone, :address, :joined_on, :status, :team_admin]

  def statuses, do: @statuses

  @doc "The form for a member, in the team's time zone, or an empty one joining `today`."
  def from_member(nil, _timezone, today), do: %__MODULE__{joined_on: today}

  def from_member(%Member{} = member, timezone, _today) do
    %__MODULE__{
      name: member.name,
      ref_id: member.ref_id,
      position: member.position,
      email: member.email,
      phone: member.phone,
      address: member.address,
      status: status(member.d4h_status),
      team_admin: member.d4h_permission in [0, 1],
      joined_on: member.joined_at && local_date(member.joined_at, timezone)
    }
  end

  # A retired member's form keeps them operational; leaving is its own button.
  defp status(status) do
    if status in Enum.map(@statuses, &elem(&1, 1)), do: status, else: "OPERATIONAL"
  end

  defp local_date(datetime, timezone),
    do: datetime |> Service.Convert.utc_to_local(timezone) |> elem(0)

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, [
      :name,
      :ref_id,
      :position,
      :email,
      :phone,
      :address,
      :status,
      :team_admin,
      :joined_on
    ])
    |> validate_required([:name], message: "Enter the member's name.")
    |> validate_required([:joined_on], message: "Enter the date they joined.")
    |> validate_length(:name, max: 100)
    |> validate_length(:ref_id, max: 100)
    |> validate_length(:position, max: 100)
    |> Validate.email(:email)
    |> validate_length(:phone, max: 30)
    |> validate_length(:address, max: 300)
    |> validate_inclusion(:status, Enum.map(@statuses, &elem(&1, 1)))
    |> Validate.in_field_order(@fields)
  end

  # :insert, not :validate, so a failed save shows the error summary.
  def validate(form, params), do: form |> changeset(params) |> apply_action(:insert)
end
