defmodule App.Repo.Migrations.AddSignatureToTeamsAndLetters do
  use Ecto.Migration

  # A PNG of the signer's signature (#194), in the row so Litestream backs it up. Each
  # letter keeps its own copy, so an old letter never shows a later signer's signature.
  def change do
    alter table(:teams) do
      add :signature, :binary
    end

    alter table(:tax_credit_letters) do
      add :signature, :binary
    end
  end
end
