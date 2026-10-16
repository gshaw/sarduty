defmodule App.Model.Organization do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  # A parent organization, like BCSARA. Its member teams' cards and check pages carry its
  # name and logo. Set up by an admin; teams can't join or leave one themselves.
  # Public paths name an organization by its slug: ~p"/orgs/#{organization}/logo".
  # Admin pages use the id.
  @derive {Phoenix.Param, key: :slug}
  schema "organizations" do
    field :name, TrimmedString
    field :short_name, TrimmedString
    field :slug, :string
    field :website, TrimmedString
    # A PNG, already sized by Service.Image.png/2 when it was uploaded.
    field :logo, :binary, redact: true
    # The D4H tags its teams count as primary and secondary hours (#289). Blank means
    # "Primary Hours" and "Secondary Hours"; see App.Model.Activity.hours_tags/1.
    field :primary_hours_tag, TrimmedString
    field :secondary_hours_tag, TrimmedString
    # The tag on activities that count for no hours, such as a social (#323). Blank lets
    # each team name its own.
    field :other_hours_tag, TrimmedString
    has_many :teams, Team
    timestamps(type: :utc_datetime_usec)
  end

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :name,
      :short_name,
      :slug,
      :website,
      :primary_hours_tag,
      :secondary_hours_tag,
      :other_hours_tag
    ])
    |> update_change(:slug, &String.downcase/1)
    |> validate_required([:name, :short_name, :slug])
    |> validate_length(:name, max: 100)
    |> validate_length(:short_name, max: 20)
    |> validate_format(:slug, ~r/^[a-z0-9-]{2,30}$/,
      message: "Use 2 to 30 lowercase letters, numbers, and dashes."
    )
    |> validate_length(:primary_hours_tag, max: 100)
    |> validate_length(:secondary_hours_tag, max: 100)
    |> validate_length(:other_hours_tag, max: 100)
    |> validate_different_hours_tags()
    |> validate_format(:website, ~r{^https://\S+$}, message: "Start the address with https://")
    |> unique_constraint(:slug)
  end

  defp validate_different_hours_tags(changeset) do
    case changeset |> apply_changes() |> Activity.hours_tags() |> Activity.repeated_hours_tag() do
      nil -> changeset
      {kind, text} -> add_error(changeset, Activity.hours_tag_field(kind), text)
    end
  end

  def get_all do
    Organization
    |> order_by([o], o.name)
    |> Repo.all()
  end

  def get!(id), do: Repo.get!(Organization, id)
  def get_by_slug(slug), do: Repo.get_by(Organization, slug: slug)

  def put_logo!(%Organization{} = record, png),
    do: record |> change(logo: png) |> Repo.update!()

  @doc "The ids of the organization's teams."
  def team_ids(%Organization{id: id}) do
    Team
    |> where([t], t.organization_id == ^id)
    |> select([t], t.id)
    |> Repo.all()
  end

  @doc "Makes these teams the organization's, and only these. A team leaves any other."
  def set_teams!(%Organization{id: id}, team_ids) do
    Repo.transaction(fn ->
      Team
      |> where([t], t.organization_id == ^id and t.id not in ^team_ids)
      |> Repo.update_all(set: [organization_id: nil])

      Team |> where([t], t.id in ^team_ids) |> Repo.update_all(set: [organization_id: id])
    end)

    :ok
  end
end
