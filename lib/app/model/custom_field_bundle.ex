defmodule App.Model.CustomFieldBundle do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Team

  # A copy of one of D4H's resource bundles (#872): a named group of one kind's custom
  # fields, such as BCSARA's "KMS Data" on incidents. The team's own or its
  # organisation's, kept by the sync with the fields. Pages show its title over its
  # fields; see App.Model.CustomField.grouped/2.
  schema "custom_field_bundles" do
    belongs_to :team, Team
    field :d4h_bundle_id, :integer
    field :title, TrimmedString
    # As a custom field's target: "incident", "member", and so on.
    field :target, :string
    field :ordering, :integer, default: 0
    # "Team" or "Organisation" and its D4H id, as for fields.
    field :owner_type, :string
    field :owner_id, :integer
    timestamps(type: :utc_datetime_usec)
  end
end
