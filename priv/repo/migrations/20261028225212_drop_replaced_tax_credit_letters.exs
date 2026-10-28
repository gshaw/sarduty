defmodule App.Repo.Migrations.DropReplacedTaxCreditLetters do
  use Ecto.Migration

  # Only a team's current tax credit letter verifies, so a replaced letter's old number,
  # hours, and certified date have no use. Production had no rows (2026-10-28).
  def up do
    drop table(:replaced_tax_credit_letters)
  end

  def down do
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
  end
end
