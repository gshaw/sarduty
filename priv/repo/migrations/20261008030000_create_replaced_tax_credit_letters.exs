defmodule App.Repo.Migrations.CreateReplacedTaxCreditLetters do
  use Ecto.Migration

  # A replaced letter's reference number, hours, and certified date (#207), so a paper
  # copy the member already has still verifies after Replace gives the letter a new one.
  def change do
    create table(:replaced_tax_credit_letters) do
      add :tax_credit_letter_id, references(:tax_credit_letters, on_delete: :delete_all),
        null: false

      add :ref_id, :string, null: false
      add :primary_minutes, :integer
      add :secondary_minutes, :integer
      add :certified_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replaced_tax_credit_letters, [:ref_id])
    create index(:replaced_tax_credit_letters, [:tax_credit_letter_id])

    # Reference numbers from before #207 (SRVTC- and 5 characters) were never checked for
    # duplicates, so only the new 8-character ones are unique.
    create unique_index(:tax_credit_letters, [:ref_id],
             where: "length(ref_id) > 11",
             name: :tax_credit_letters_current_ref_id_index
           )
  end
end
