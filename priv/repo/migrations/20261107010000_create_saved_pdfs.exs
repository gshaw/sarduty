defmodule App.Repo.Migrations.CreateSavedPdfs do
  use Ecto.Migration

  # One table of saved PDFs for any document (#950, step 1): a tax credit letter's, or a
  # form's for an activity. Letters' PDFs move over with their ids, so nothing a
  # download or email serves changes. The bytes stay in their own table. Step 3 adds
  # `form_id` and `form_version` with the forms table: SQLite can add a column that
  # references a table, but not a reference to a column that's already there.
  def up do
    create table(:saved_pdfs) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :tax_credit_letter_id, references(:tax_credit_letters, on_delete: :delete_all)
      add :activity_id, references(:activities, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :filename, :string, null: false
      add :byte_size, :integer, null: false
      add :keep, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:saved_pdfs, [:tax_credit_letter_id])
    create index(:saved_pdfs, [:team_id])
    create index(:saved_pdfs, [:activity_id])

    create table(:saved_pdf_files) do
      add :saved_pdf_id, references(:saved_pdfs, on_delete: :delete_all), null: false
      add :bytes, :binary, null: false
    end

    create unique_index(:saved_pdf_files, [:saved_pdf_id])

    execute """
    INSERT INTO saved_pdfs (id, team_id, tax_credit_letter_id, title, filename, byte_size, keep, inserted_at)
    SELECT id, team_id, tax_credit_letter_id, title, filename, byte_size, '{}', inserted_at FROM letter_pdfs
    """

    execute """
    INSERT INTO saved_pdf_files (id, saved_pdf_id, bytes)
    SELECT id, letter_pdf_id, bytes FROM letter_pdf_files
    """

    drop table(:letter_pdf_files)
    drop table(:letter_pdfs)
  end

  def down do
    create table(:letter_pdfs) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      add :tax_credit_letter_id, references(:tax_credit_letters, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :filename, :string, null: false
      add :byte_size, :integer, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:letter_pdfs, [:tax_credit_letter_id])
    create index(:letter_pdfs, [:team_id])

    create table(:letter_pdf_files) do
      add :letter_pdf_id, references(:letter_pdfs, on_delete: :delete_all), null: false
      add :bytes, :binary, null: false
    end

    create unique_index(:letter_pdf_files, [:letter_pdf_id])

    # A form's PDFs have no letter to go back to, so down drops them.
    execute """
    INSERT INTO letter_pdfs (id, team_id, tax_credit_letter_id, title, filename, byte_size, inserted_at)
    SELECT id, team_id, tax_credit_letter_id, title, filename, byte_size, inserted_at
    FROM saved_pdfs WHERE tax_credit_letter_id IS NOT NULL
    """

    execute """
    INSERT INTO letter_pdf_files (id, letter_pdf_id, bytes)
    SELECT f.id, f.saved_pdf_id, f.bytes FROM saved_pdf_files f
    JOIN saved_pdfs p ON p.id = f.saved_pdf_id WHERE p.tax_credit_letter_id IS NOT NULL
    """

    drop table(:saved_pdf_files)
    drop table(:saved_pdfs)
  end
end
