defmodule App.Repo.Migrations.SortActivityTags do
  use Ecto.Migration

  # Activities store their tags sorted from now on (#358). Sorting the rows here, rather
  # than letting the next sync do it, keeps change history free of order-only changes.
  def up do
    execute("""
    UPDATE activities
    SET tags = (SELECT json_group_array(value) FROM (SELECT value FROM json_each(activities.tags) ORDER BY value))
    WHERE tags IS NOT NULL AND json_array_length(tags) > 1
    """)
  end

  def down, do: :ok
end
