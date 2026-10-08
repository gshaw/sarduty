defmodule App.ViewModel.HostedTeamViewModel do
  use App, :view_model

  alias App.Field
  alias App.Validate

  # Canada's zones, east to west. Hosted teams so far are Canadian.
  @timezones [
    {"Newfoundland", "America/St_Johns"},
    {"Atlantic", "America/Halifax"},
    {"Eastern", "America/Toronto"},
    {"Central", "America/Winnipeg"},
    {"Saskatchewan", "America/Regina"},
    {"Mountain", "America/Edmonton"},
    {"Pacific", "America/Vancouver"},
    {"Yukon", "America/Whitehorse"}
  ]

  @primary_key false
  embedded_schema do
    field :name, Field.TrimmedString
    field :subdomain, Field.TrimmedString
    field :timezone, :string, default: "America/Halifax"
    field :manager_name, Field.TrimmedString
    field :manager_email, Field.TrimmedString
    field :sample_data, :boolean, default: false
  end

  def timezones, do: @timezones

  def build_new_changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:name, :subdomain, :timezone, :manager_name, :manager_email, :sample_data])
    |> update_change(:subdomain, &String.downcase/1)
    |> validate_required([:name, :subdomain, :timezone, :manager_name, :manager_email])
    |> Validate.name(:name)
    |> validate_format(:subdomain, ~r/^[a-z][a-z0-9-]{2,29}$/,
      message: "Use 3 to 30 lowercase letters, numbers, and dashes, starting with a letter."
    )
    |> validate_inclusion(:timezone, Enum.map(@timezones, &elem(&1, 1)))
    |> validate_length(:manager_name, max: 100)
    |> validate_format(:manager_email, ~r/^[^\s]+@[^\s]+$/,
      message: "Enter an email with an @ sign and no spaces."
    )
    |> validate_length(:manager_email, max: 160)
  end

  def validate(params), do: params |> build_new_changeset() |> apply_action(:insert)
end
