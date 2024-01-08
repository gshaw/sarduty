defmodule App.Repo.Migrations.CreateTaxCreditLetters do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :authorized_by_name, :string
    end

    create table(:tax_credit_letters) do
      add :member_id, references(:members), null: false
      add :ref_id, :string, null: false
      add :year, :integer, null: false
      add :letter_content, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:tax_credit_letters, [:member_id, :year])
  end
end
