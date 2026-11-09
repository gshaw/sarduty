defmodule App.Repo.Migrations.CreatePublishedPdfs do
  use Ecto.Migration

  import Ecto.Query

  # Saved PDFs become published PDFs (#970): only a published PDF is saved, each with an
  # ID the verify site finds it by. A subject has one current PDF for each definition;
  # one it replaced stays, marked Replaced. Every saved PDF in production is a tax
  # credit letter's: each moves over with the letter's hours as what its verify page
  # shows, and the letter's date as when it was published. Its old reference number
  # comes along as its code until App.Worker.RenewLetterCodesWorker, run once after
  # deploy, gives it an ID and prints it again; an old number never verifies. A form's
  # saved PDF was a draft from before drafts stopped being saved, so it goes.
  #
  # SQLite changes no foreign key or unique index in place, so the tables are made new
  # and the rows copied.
  def up do
    create table(:published_pdfs) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      # The definition's name, and what it's for: `member:45:2026` or `activity:812`.
      add :name, :string, null: false
      add :subject, :string, null: false
      add :code, :string, null: false
      add :tax_credit_letter_id, references(:tax_credit_letters, on_delete: :delete_all)
      add :member_id, references(:members, on_delete: :delete_all)
      add :year, :integer
      add :activity_id, references(:activities, on_delete: :delete_all)
      add :form_id, references(:forms, on_delete: :nilify_all)
      add :form_version, :integer
      add :user_id, references(:users, on_delete: :nilify_all)
      add :replaced_by_id, references(:published_pdfs, on_delete: :nilify_all)
      add :withdrawn_at, :utc_datetime_usec
      add :withdrawn_by_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :filename, :string, null: false
      add :byte_size, :integer, null: false
      add :sha256, :string
      add :keep, :map, null: false, default: %{}
      add :answers, :map, null: false, default: %{}
      # What the verify page shows, `[%{label, text}]` as `verify shows` printed it.
      add :shows, :text, null: false, default: "[]"
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # A reference number from before #207 has 5 characters and was never unique.
    create unique_index(:published_pdfs, [:code],
             where: "length(code) > 11",
             name: :published_pdfs_unique_code_index
           )

    create index(:published_pdfs, [:code])

    create unique_index(:published_pdfs, [:team_id, :name, :subject],
             where: "replaced_by_id IS NULL AND withdrawn_at IS NULL",
             name: :published_pdfs_current_index
           )

    create index(:published_pdfs, [:tax_credit_letter_id])
    create index(:published_pdfs, [:member_id])
    create index(:published_pdfs, [:activity_id])
    create index(:published_pdfs, [:form_id])
    create index(:published_pdfs, [:replaced_by_id])

    create table(:published_pdf_files) do
      add :published_pdf_id, references(:published_pdfs, on_delete: :delete_all), null: false
      add :bytes, :binary, null: false
    end

    create unique_index(:published_pdf_files, [:published_pdf_id])

    flush()
    copy_letters()

    drop index(:tax_credit_letters, [:ref_id], name: :tax_credit_letters_current_ref_id_index)

    alter table(:tax_credit_letters) do
      remove :ref_id
    end

    drop table(:saved_pdf_files)
    drop table(:saved_pdfs)
  end

  defp copy_letters do
    execute """
    INSERT INTO published_pdfs (id, team_id, name, subject, code, tax_credit_letter_id,
      member_id, year, title, filename, byte_size, keep, inserted_at)
    SELECT p.id, p.team_id, 'Tax credit letter', 'member:' || l.member_id || ':' || l.year,
      l.ref_id, l.id, l.member_id, l.year, p.title, p.filename, p.byte_size,
      json_object('hours.primary', l.primary_minutes, 'hours.secondary', l.secondary_minutes),
      l.inserted_at
    FROM saved_pdfs p JOIN tax_credit_letters l ON l.id = p.tax_credit_letter_id
    """

    execute """
    INSERT INTO published_pdf_files (id, published_pdf_id, bytes)
    SELECT f.id, f.saved_pdf_id, f.bytes FROM saved_pdf_files f
    JOIN published_pdfs p ON p.id = f.saved_pdf_id
    """

    flush()

    # What each letter's verify page shows, as the letter verify page showed it, and
    # each file's checksum.
    rows =
      repo().all(
        from(p in "published_pdfs",
          join: l in "tax_credit_letters",
          on: l.id == p.tax_credit_letter_id,
          join: m in "members",
          on: m.id == l.member_id,
          join: f in "published_pdf_files",
          on: f.published_pdf_id == p.id,
          select: {p.id, m.name, l.year, l.primary_minutes, l.secondary_minutes, f.bytes}
        )
      )

    for {id, name, year, primary, secondary, bytes} <- rows do
      shows =
        [{"Name", name}, {"Year", to_string(year)}] ++
          if primary && secondary,
            do: [
              {"Primary hours", duration(primary)},
              {"Secondary hours", duration(secondary)},
              {"Total hours", duration(primary + secondary)}
            ],
            else: []

      repo().update_all(from(p in "published_pdfs", where: p.id == ^id),
        set: [
          shows:
            Jason.encode!(Enum.map(shows, fn {label, text} -> %{label: label, text: text} end)),
          sha256: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
        ]
      )
    end
  end

  # Service.Format.duration/1 as it was on 2026-11-09, so this migration never changes.
  defp duration(minutes) do
    {hours, mins} = {div(minutes, 60), rem(minutes, 60)}

    cond do
      hours == 1 and mins == 0 -> "1 hour"
      mins == 0 -> "#{thousands(hours)} hours"
      hours == 0 -> "#{mins} min"
      true -> "#{thousands(hours)}h #{mins}m"
    end
  end

  defp thousands(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  # Down makes step 1's saved_pdfs again, with the forms columns, and gives each letter
  # back its current PDF's reference number. Replaced PDFs have no place there, so they
  # go. A letter with no PDF gets a new 8-character reference number.
  def down do
    alter table(:tax_credit_letters) do
      add :ref_id, :string
    end

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
      add :form_id, references(:forms, on_delete: :nilify_all)
      add :form_version, :integer
    end

    create unique_index(:saved_pdfs, [:tax_credit_letter_id])
    create index(:saved_pdfs, [:team_id])
    create index(:saved_pdfs, [:activity_id])
    create index(:saved_pdfs, [:form_id])

    create table(:saved_pdf_files) do
      add :saved_pdf_id, references(:saved_pdfs, on_delete: :delete_all), null: false
      add :bytes, :binary, null: false
    end

    create unique_index(:saved_pdf_files, [:saved_pdf_id])

    flush()

    execute """
    INSERT INTO saved_pdfs (id, team_id, tax_credit_letter_id, title, filename, byte_size, keep, inserted_at)
    SELECT id, team_id, tax_credit_letter_id, title, filename, byte_size, keep, inserted_at
    FROM published_pdfs
    WHERE tax_credit_letter_id IS NOT NULL AND replaced_by_id IS NULL AND withdrawn_at IS NULL
    """

    execute """
    INSERT INTO saved_pdf_files (id, saved_pdf_id, bytes)
    SELECT f.id, f.published_pdf_id, f.bytes FROM published_pdf_files f
    JOIN saved_pdfs p ON p.id = f.published_pdf_id
    """

    execute """
    UPDATE tax_credit_letters SET ref_id = (
      SELECT code FROM published_pdfs p WHERE p.tax_credit_letter_id = tax_credit_letters.id
      AND p.replaced_by_id IS NULL AND p.withdrawn_at IS NULL)
    """

    flush()

    for id <-
          repo().all(from(l in "tax_credit_letters", where: is_nil(l.ref_id), select: l.id)) do
      repo().update_all(from(l in "tax_credit_letters", where: l.id == ^id),
        set: [ref_id: "SRVTC-" <> old_code()]
      )
    end

    create unique_index(:tax_credit_letters, [:ref_id],
             where: "length(ref_id) > 11",
             name: :tax_credit_letters_current_ref_id_index
           )

    drop table(:published_pdf_files)
    drop table(:published_pdfs)
  end

  # 8 characters from the ID card alphabet, as reference numbers were.
  # cspell:ignore ABCDEFGHJKMNPQRSTVWXYZ
  defp old_code do
    alphabet = ~c"23456789ABCDEFGHJKMNPQRSTVWXYZ"
    for _ <- 1..8, into: "", do: <<Enum.random(alphabet)>>
  end
end
