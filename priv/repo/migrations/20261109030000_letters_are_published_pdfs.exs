defmodule App.Repo.Migrations.LettersArePublishedPdfs do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # A tax credit letter is its published PDF (#970, part 3): its ID, hours, and date are
  # already there, and its first download and email status move over, onto its current
  # PDF. `tax_credit_letters` goes, with each letter's text: the letter page shows what
  # its verify page shows instead. A letter with no PDF never left SAR Duty and goes too;
  # production had none (2026-11-07, 232 letters and 232 PDFs).
  #
  # SQLite drops no column a foreign key is on, so published_pdfs is rebuilt without
  # `tax_credit_letter_id`. Dropping it with foreign keys on would delete its files by
  # cascade, so they go off first. That pragma does nothing inside a transaction, so this
  # migration runs outside Ecto's, on one connection, and copies inside its own.
  @disable_ddl_transaction true

  # Part 1's App.Worker.RenewLetterCodesWorker gives each letter from before #970 an ID
  # and prints it again from its letter's row. It needs the letters table, so this waits
  # until it's done: then every code is an ID, and the code index is plainly unique.

  @columns ~w(id team_id name subject code member_id year activity_id form_id form_version
              user_id replaced_by_id withdrawn_at withdrawn_by_id title filename byte_size
              sha256 keep answers shows inserted_at)

  def up do
    check_codes_renewed()

    run([
      table_sql("published_pdfs_new", ~s|"first_opened_at" TEXT, "email_status" TEXT,|),
      """
      INSERT INTO published_pdfs_new (#{columns()}, first_opened_at, email_status)
      SELECT #{columns("p.")}, l.downloaded_at, l.email_status
      FROM published_pdfs p
      LEFT JOIN tax_credit_letters l ON l.id = p.tax_credit_letter_id
        AND p.replaced_by_id IS NULL AND p.withdrawn_at IS NULL
      """,
      "DROP TABLE published_pdfs",
      "ALTER TABLE published_pdfs_new RENAME TO published_pdfs",
      "DROP TABLE tax_credit_letters"
      | indexes()
    ])
  end

  # Each letter comes back from its current PDF, with its hours and an empty text. Its
  # replaced PDFs point at it too.
  def down do
    run([
      """
      CREATE TABLE "tax_credit_letters" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "member_id" INTEGER NOT NULL CONSTRAINT "tax_credit_letters_member_id_fkey" REFERENCES "members"("id"),
        "year" INTEGER NOT NULL,
        "letter_content" TEXT NOT NULL,
        "inserted_at" TEXT NOT NULL,
        "primary_minutes" INTEGER,
        "secondary_minutes" INTEGER,
        "downloaded_at" TEXT,
        "email_status" TEXT
      )
      """,
      ~s|CREATE UNIQUE INDEX "tax_credit_letters_member_id_year_index" ON "tax_credit_letters" ("member_id", "year")|,
      """
      INSERT INTO tax_credit_letters (id, member_id, year, letter_content, inserted_at,
        primary_minutes, secondary_minutes, downloaded_at, email_status)
      SELECT id, member_id, year, '', inserted_at, json_extract(keep, '$."hours.primary"'),
        json_extract(keep, '$."hours.secondary"'), first_opened_at, email_status
      FROM published_pdfs
      WHERE name = 'Tax credit letter' AND replaced_by_id IS NULL AND withdrawn_at IS NULL
      """,
      table_sql(
        "published_pdfs_new",
        ~s|"tax_credit_letter_id" INTEGER CONSTRAINT "published_pdfs_tax_credit_letter_id_fkey" REFERENCES "tax_credit_letters"("id") ON DELETE CASCADE,|
      ),
      """
      INSERT INTO published_pdfs_new (#{columns()}, tax_credit_letter_id)
      SELECT #{columns("p.")}, l.id FROM published_pdfs p
      LEFT JOIN tax_credit_letters l ON p.name = 'Tax credit letter'
        AND l.member_id = p.member_id AND l.year = p.year
      """,
      "DROP TABLE published_pdfs",
      "ALTER TABLE published_pdfs_new RENAME TO published_pdfs",
      ~s|CREATE INDEX "published_pdfs_tax_credit_letter_id_index" ON "published_pdfs" ("tax_credit_letter_id")|
      | indexes()
    ])
  end

  defp check_codes_renewed do
    %{rows: [[old]]} =
      repo().query!("SELECT count(*) FROM published_pdfs WHERE length(code) != 15")

    if old > 0,
      do:
        raise(
          "#{old} published PDFs still have a code from before #970. " <>
            "Run App.Worker.RenewLetterCodesWorker.enqueue() on part 1 first."
        )
  end

  defp run(statements) do
    repo = repo()

    repo.checkout(fn ->
      repo.query!("PRAGMA foreign_keys = OFF")

      try do
        repo.transaction(fn -> Enum.each(statements, &repo.query!/1) end)
      after
        repo.query!("PRAGMA foreign_keys = ON")
      end
    end)
  end

  defp columns(prefix \\ ""), do: Enum.map_join(@columns, ", ", &(prefix <> &1))

  # The table as part 1 made it, less the letter's column, plus `extra`.
  defp table_sql(name, extra) do
    """
    CREATE TABLE "#{name}" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER NOT NULL CONSTRAINT "published_pdfs_team_id_fkey" REFERENCES "teams"("id") ON DELETE CASCADE,
      "name" TEXT NOT NULL,
      "subject" TEXT NOT NULL,
      "code" TEXT NOT NULL,
      "member_id" INTEGER CONSTRAINT "published_pdfs_member_id_fkey" REFERENCES "members"("id") ON DELETE CASCADE,
      "year" INTEGER,
      "activity_id" INTEGER CONSTRAINT "published_pdfs_activity_id_fkey" REFERENCES "activities"("id") ON DELETE CASCADE,
      "form_id" INTEGER CONSTRAINT "published_pdfs_form_id_fkey" REFERENCES "forms"("id") ON DELETE SET NULL,
      "form_version" INTEGER,
      "user_id" INTEGER CONSTRAINT "published_pdfs_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "replaced_by_id" INTEGER CONSTRAINT "published_pdfs_replaced_by_id_fkey" REFERENCES "published_pdfs"("id") ON DELETE SET NULL,
      "withdrawn_at" TEXT,
      "withdrawn_by_id" INTEGER CONSTRAINT "published_pdfs_withdrawn_by_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "title" TEXT NOT NULL,
      "filename" TEXT NOT NULL,
      "byte_size" INTEGER NOT NULL,
      "sha256" TEXT,
      "keep" TEXT DEFAULT ('{}') NOT NULL,
      "answers" TEXT DEFAULT ('{}') NOT NULL,
      "shows" TEXT DEFAULT '[]' NOT NULL,
      #{extra}
      "inserted_at" TEXT NOT NULL
    )
    """
  end

  defp indexes do
    [
      ~s|CREATE UNIQUE INDEX "published_pdfs_code_index" ON "published_pdfs" ("code")|,
      ~s|CREATE UNIQUE INDEX "published_pdfs_current_index" ON "published_pdfs" ("team_id", "name", "subject") WHERE replaced_by_id IS NULL AND withdrawn_at IS NULL|,
      ~s|CREATE INDEX "published_pdfs_member_id_index" ON "published_pdfs" ("member_id")|,
      ~s|CREATE INDEX "published_pdfs_activity_id_index" ON "published_pdfs" ("activity_id")|,
      ~s|CREATE INDEX "published_pdfs_form_id_index" ON "published_pdfs" ("form_id")|,
      ~s|CREATE INDEX "published_pdfs_replaced_by_id_index" ON "published_pdfs" ("replaced_by_id")|
    ]
  end
end
