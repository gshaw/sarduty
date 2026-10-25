defmodule App.Repo.Migrations.AddEmailStatusToTaxCreditLetters do
  use Ecto.Migration

  # Sending every letter at once queues one email job per letter (#516), so each letter
  # keeps whether its email went. Letters made before have none.
  def change do
    alter table(:tax_credit_letters) do
      add :email_status, :string
    end
  end
end
