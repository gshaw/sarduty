defmodule App.Repo.Migrations.AddDetailsToTemplates do
  use Ecto.Migration

  # A template's activity details, which fill Add activity (#746): title, start time,
  # duration, place and pin, tax credit hours, and description. Tax credit hours replaces
  # the hours tag a template held, so each template's Primary or Secondary Hours tag
  # moves into it and leaves its tags. A template with neither gets Neither, since
  # applying a template adds its hours tag to an activity with none, and that one added
  # none before. A new template gets Primary. The tag names are the team's, as App.Model.Activity.hours_tags/1 reads
  # them: its organization's, then its own, then the defaults.
  @hours_tags """
  SELECT tt.id, tt.template_id, tags.title = h.primary_tag, tags.title = h.secondary_tag
  FROM template_tags tt
  JOIN templates ON templates.id = tt.template_id
  JOIN tags ON tags.id = tt.tag_id
  JOIN (
    SELECT teams.id AS team_id,
      COALESCE(NULLIF(o.primary_hours_tag, ''), NULLIF(teams.primary_hours_tag, ''), 'Primary Hours') AS primary_tag,
      COALESCE(NULLIF(o.secondary_hours_tag, ''), NULLIF(teams.secondary_hours_tag, ''), 'Secondary Hours') AS secondary_tag
    FROM teams LEFT JOIN organizations o ON o.id = teams.organization_id
  ) h ON h.team_id = templates.team_id
  WHERE tags.title IN (h.primary_tag, h.secondary_tag)
  """

  def up do
    alter table(:templates) do
      add :activity_title, :string
      add :start_time, :time
      add :duration_minutes, :integer
      add :place, :string
      add :coordinate, :string
      add :hours, :string, null: false, default: "primary"
      add :description, :text
    end

    flush()

    %{rows: rows} = repo().query!(@hours_tags)
    repo().query!("UPDATE templates SET hours = 'none'")

    # Primary wins when a template has both, as Activity.counts_as/2 reads them.
    rows
    |> Enum.group_by(fn [_id, template_id, _primary, _secondary] -> template_id end)
    |> Enum.each(fn {template_id, tags} ->
      primary? = Enum.any?(tags, fn [_id, _template_id, primary, _secondary] -> primary == 1 end)
      hours = if primary?, do: "primary", else: "secondary"
      repo().query!("UPDATE templates SET hours = ? WHERE id = ?", [hours, template_id])
    end)

    for [id | _rest] <- rows, do: repo().query!("DELETE FROM template_tags WHERE id = ?", [id])
  end

  # The hours go back as tags only where the team has the tag in its copy.
  def down do
    execute("""
    INSERT INTO template_tags (template_id, tag_id, inserted_at, updated_at)
    SELECT templates.id, tags.id, templates.updated_at, templates.updated_at
    FROM templates
    JOIN teams ON teams.id = templates.team_id
    LEFT JOIN organizations o ON o.id = teams.organization_id
    JOIN tags ON tags.team_id = templates.team_id AND tags.title =
      CASE templates.hours
        WHEN 'primary' THEN COALESCE(NULLIF(o.primary_hours_tag, ''), NULLIF(teams.primary_hours_tag, ''), 'Primary Hours')
        WHEN 'secondary' THEN COALESCE(NULLIF(o.secondary_hours_tag, ''), NULLIF(teams.secondary_hours_tag, ''), 'Secondary Hours')
      END
    """)

    alter table(:templates) do
      remove :activity_title
      remove :start_time
      remove :duration_minutes
      remove :place
      remove :coordinate
      remove :hours
      remove :description
    end
  end
end
