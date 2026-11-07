defmodule App.Repo.Migrations.CreateForms do
  use Ecto.Migration

  # An organization's forms (#950, step 3): its text and its page PDF, with the bytes in
  # their own table. Saved PDFs gain the form and version they printed from, which step 1
  # left for now: SQLite adds a column that references a table, but can't add a
  # reference to a column already there.
  def up do
    create table(:forms) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :about, :string
      add :text, :text, null: false
      add :page_sha256, :string
      add :enabled, :boolean, null: false, default: false
      add :version, :integer, null: false, default: 1
      add :user_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:forms, [:organization_id, :name])

    create table(:form_pages) do
      add :form_id, references(:forms, on_delete: :delete_all), null: false
      add :bytes, :binary, null: false
    end

    create unique_index(:form_pages, [:form_id])

    alter table(:saved_pdfs) do
      add :form_id, references(:forms, on_delete: :nilify_all)
      add :form_version, :integer
    end

    create index(:saved_pdfs, [:form_id])
  end

  # SQLite drops no column a foreign key is on, so down copies saved PDFs out, makes
  # step 1's tables again, and copies them back. Dropping saved_pdfs first would delete
  # their files by cascade.
  def down do
    execute """
    CREATE TABLE saved_pdfs_down AS
    SELECT id, team_id, tax_credit_letter_id, activity_id, user_id, title, filename,
           byte_size, keep, inserted_at FROM saved_pdfs
    """

    execute "CREATE TABLE saved_pdf_files_down AS SELECT id, saved_pdf_id, bytes FROM saved_pdf_files"

    drop table(:saved_pdf_files)
    drop table(:saved_pdfs)

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

    execute "INSERT INTO saved_pdfs SELECT * FROM saved_pdfs_down"
    execute "INSERT INTO saved_pdf_files SELECT * FROM saved_pdf_files_down"
    execute "DROP TABLE saved_pdfs_down"
    execute "DROP TABLE saved_pdf_files_down"

    drop table(:form_pages)
    drop table(:forms)
  end
end
