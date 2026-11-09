defmodule App.Repo.Migrations.AddStateToForms do
  use Ecto.Migration

  # A form is Off, Testing, or On for an organization's teams (#970): testing prints draft
  # PDFs only, and on publishes. Every form turned on so far was for testing, under the
  # Testing only banner, so on becomes testing.
  def up do
    alter table(:forms) do
      add :state, :string, null: false, default: "off"
    end

    execute "UPDATE forms SET state = 'testing' WHERE enabled"

    alter table(:forms) do
      remove :enabled
    end
  end

  def down do
    alter table(:forms) do
      add :enabled, :boolean, null: false, default: false
    end

    execute "UPDATE forms SET enabled = state != 'off'"

    alter table(:forms) do
      remove :state
    end
  end
end
