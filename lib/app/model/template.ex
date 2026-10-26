defmodule App.Model.Template do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.Team
  alias App.Model.Template
  alias App.Model.TemplateGroup
  alias App.Model.TemplateItem
  alias App.Model.TemplateTag
  alias App.Repo

  # A named set of equipment items, each with default hours, tags, and groups whose
  # members it adds, that a team admin applies to an activity in one step (#271, #162). Templates are SAR Duty's
  # own; D4H never sees them.
  schema "templates" do
    belongs_to :team, Team
    has_many :template_items, TemplateItem, on_replace: :delete
    has_many :template_tags, TemplateTag, on_replace: :delete
    has_many :template_groups, TemplateGroup, on_replace: :delete
    field :title, TrimmedString
    timestamps(type: :utc_datetime_usec)
  end

  @preloads [template_items: :equipment_item, template_tags: :tag, template_groups: :group]

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:title])
    |> validate_required([:title], message: "Enter a name for the template")
    |> validate_length(:title, max: 100)
  end

  @doc "A team's templates by title, with their items, tags, and groups."
  def get_all(team_id) do
    Template
    |> where([k], k.team_id == ^team_id)
    |> order_by([k], asc: k.title, asc: k.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  def find!(%Team{} = team, id) do
    Template
    |> Repo.get_by!(id: id, team_id: team.id)
    |> Repo.preload(@preloads)
  end

  @doc "The template's tags by title."
  def tags(%Template{template_tags: template_tags}),
    do: template_tags |> Enum.map(& &1.tag) |> Enum.sort_by(&String.downcase(&1.title))

  @doc "The groups whose members the template adds, by title."
  def groups(%Template{template_groups: template_groups}),
    do: template_groups |> Enum.map(& &1.group) |> Enum.sort_by(&String.downcase(&1.title))
end
