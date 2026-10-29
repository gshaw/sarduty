defmodule App.Repo.Migrations.AddKindAndCustomValuesToTemplates do
  use Ecto.Migration

  # A template's kind of activity, and its values for that kind's D4H custom fields,
  # keyed by D4H field id as on activities (#307). Nil on the templates there are now.
  def change do
    alter table(:templates) do
      add :activity_kind, :string
      add :custom_values, :map
    end
  end
end
