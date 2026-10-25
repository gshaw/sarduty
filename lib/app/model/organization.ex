defmodule App.Model.Organization do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Activity
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  # A parent organization, like BCSARA. Its member teams' cards and check pages carry its
  # name and logo. Its own space is /orgs/:slug (#512): its organization admins keep its
  # settings, and SAR Duty admins add and remove its teams. Paths name it by its slug:
  # ~p"/orgs/#{organization}/logo".
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
    # For dates about the organization, such as an organization admin's Last seen. A
    # team's own dates keep the team's zone.
    field :timezone, :string, default: "America/Vancouver"
    has_many :teams, Team
    timestamps(type: :utc_datetime_usec)
  end

  @doc "General settings, for its organization admins: no slug, no hours tags."
  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:name, :short_name, :website, :timezone])
    |> validate_general()
  end

  @doc "A new organization, from Admin › Organizations: General's fields and the slug."
  def build_new_changeset(params \\ %{}) do
    %Organization{}
    |> cast(params, [:name, :short_name, :slug, :timezone])
    |> update_change(:slug, &String.downcase/1)
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]{2,30}$/,
      message: "Use 2 to 30 lowercase letters, numbers, and dashes."
    )
    |> unique_constraint(:slug, message: "Another organization uses this slug.")
    |> validate_general()
  end

  defp validate_general(changeset) do
    changeset
    |> validate_required([:name, :short_name, :timezone])
    |> validate_length(:name, max: 100)
    |> validate_length(:short_name, max: 20)
    |> validate_inclusion(:timezone, Tzdata.zone_list(), message: "Select a time zone.")
    |> validate_format(:website, ~r{^https://\S+$}, message: "Start the address with https://")
  end

  @doc """
  The hours tags its teams count (#289). `teams` are the organization's teams: a tag that
  would repeat one a team names itself is refused, naming the team.
  """
  def build_hours_tags_changeset(data, teams, params \\ %{}) do
    data
    |> cast(params, [:primary_hours_tag, :secondary_hours_tag, :other_hours_tag])
    |> validate_length(:primary_hours_tag, max: 100)
    |> validate_length(:secondary_hours_tag, max: 100)
    |> validate_length(:other_hours_tag, max: 100)
    |> validate_different_hours_tags()
    |> validate_teams_hours_tags(teams)
  end

  defp validate_different_hours_tags(changeset) do
    case changeset |> apply_changes() |> Activity.hours_tags() |> Activity.repeated_hours_tag() do
      nil -> changeset
      {kind, text} -> add_error(changeset, Activity.hours_tag_field(kind), text)
    end
  end

  # Each team's tags with these ones on top, as its letters would count them. A clash
  # only counts when one of the two tags is the organization's.
  defp validate_teams_hours_tags(%{errors: []} = changeset, teams) do
    organization = apply_changes(changeset)
    own = Activity.organization_hours_tags(organization)

    Enum.find_value(teams, changeset, fn team ->
      merged = Activity.hours_tags(%{team | organization: organization})

      with {kind, _text} <- Activity.repeated_hours_tag(merged),
           field_kind when field_kind != nil <- own_kind(own, merged, kind) do
        add_error(
          changeset,
          Activity.hours_tag_field(field_kind),
          "#{team.name} uses #{merged[kind]} for another kind of hours. Use a different tag."
        )
      else
        _none -> nil
      end
    end)
  end

  defp validate_teams_hours_tags(changeset, _teams), do: changeset

  # Which of the two repeated kinds the organization sets, or nil when neither.
  defp own_kind(own, merged, kind) do
    tag = String.downcase(merged[kind])

    other =
      Enum.find([:primary, :secondary, :other], fn other ->
        other != kind and is_binary(merged[other]) and String.downcase(merged[other]) == tag
      end)

    cond do
      own[kind] -> kind
      other && own[other] -> other
      true -> nil
    end
  end

  @doc "Every time zone, for the combobox."
  def timezone_options, do: Tzdata.zone_list()

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
end
