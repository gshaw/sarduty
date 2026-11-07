defmodule App.Repo.Migrations.CreateLetterPdfs do
  use Ecto.Migration

  # Each tax credit letter's PDF as it was made (#918), so a download or email serves
  # the same file every time. The bytes are in their own table, so lists never load
  # them. App.Worker.SaveLetterPDFsWorker makes one for each letter made before this.
  def change do
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
  end
end
