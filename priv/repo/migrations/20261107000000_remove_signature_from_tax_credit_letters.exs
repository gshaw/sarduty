defmodule App.Repo.Migrations.RemoveSignatureFromTaxCreditLetters do
  use Ecto.Migration

  # A letter's PDF is saved when it's made (#918) and holds the signature, so the letter
  # needs no copy of its own. Down brings the column back empty.
  def change do
    alter table(:tax_credit_letters) do
      remove :signature, :binary
    end
  end
end
