defmodule App.Repo.Migrations.AddGooglePassFingerprintToMemberCards do
  use Ecto.Migration

  # The Google Wallet pass as last sent to Google. Nil until the card's pass is first
  # made, so it also says which cards have a pass to update.
  def change do
    alter table(:member_cards) do
      add :google_pass_fingerprint, :string
    end
  end
end
