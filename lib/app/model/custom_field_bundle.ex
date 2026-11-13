defmodule App.Model.CustomFieldBundle do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.CustomFieldBundle
  alias App.Model.Team
  alias App.Repo

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

  @doc "Every bundle the team has, its organisation's too."
  def get_all(team_id), do: CustomFieldBundle |> where(team_id: ^team_id) |> Repo.all()

  @doc """
  Where a new bundle of the team's own on `target` goes: after its others. D4H takes 0
  to 255.
  """
  def next_ordering(bundles, target) do
    bundles
    |> Enum.filter(&(&1.owner_type == "Team" and &1.target == target))
    |> Enum.map(&(&1.ordering + 1))
    |> Enum.max(fn -> 0 end)
    |> min(255)
  end
end
