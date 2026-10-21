defmodule App.Operation.SaveChoreCategory do
  @moduledoc """
  Saves, archives, and restores a chore category (#341). Categories are SAR Duty's own;
  D4H sees them only as the title and tags of the events SAR Duty sends.

  `tag_ids` are local ids. A tag that isn't the team's is dropped.
  """

  import Ecto.Query

  alias App.Model.ChoreCategory
  alias App.Model.ChoreCategoryTag
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, category}`, or `{:error, changeset}` to show on the form."
  def save(%Team{} = team, category, params, tag_ids) do
    (category || %ChoreCategory{team_id: team.id, chore_category_tags: []})
    |> ChoreCategory.build_changeset(params)
    |> Ecto.Changeset.put_assoc(:chore_category_tags, category_tags(team, tag_ids))
    |> Repo.insert_or_update()
  end

  @doc "Archives the category, so members cannot pick it, or restores it with `nil`."
  def archive(%Team{} = team, %ChoreCategory{team_id: team_id} = category, archived_at)
      when team_id == team.id do
    category |> Ecto.Changeset.change(archived_at: archived_at) |> Repo.update()
  end

  defp category_tags(team, tag_ids) do
    tag_ids = Enum.uniq(tag_ids)

    team_ids =
      Tag
      |> where([t], t.team_id == ^team.id and t.id in ^tag_ids)
      |> select([t], t.id)
      |> Repo.all()
      |> MapSet.new()

    for id <- tag_ids, MapSet.member?(team_ids, id), do: %ChoreCategoryTag{tag_id: id}
  end
end
