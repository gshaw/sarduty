defmodule App.Repo.Migrations.AddHoursToTaxCreditLetters do
  use Ecto.Migration

  # Letters keep the hours they were created with (#192). Existing letters get theirs
  # from their own text; one that does not parse stays empty.
  def up do
    alter table(:tax_credit_letters) do
      add :primary_minutes, :integer
      add :secondary_minutes, :integer
    end

    flush()

    %{rows: rows} = repo().query!("SELECT id, letter_content FROM tax_credit_letters")

    for [id, content] <- rows,
        {primary, secondary} <- [App.Model.TaxCreditLetter.parse_minutes(content)] do
      repo().query!(
        "UPDATE tax_credit_letters SET primary_minutes = ?, secondary_minutes = ? WHERE id = ?",
        [primary, secondary, id]
      )
    end
  end

  def down do
    alter table(:tax_credit_letters) do
      remove :primary_minutes
      remove :secondary_minutes
    end
  end
end
