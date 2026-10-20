defmodule App.Repo.Migrations.AddDownloadedAtAndInWalletAt do
  use Ecto.Migration

  # For a member's "For you to do" (#389): a new tax credit letter until the member
  # downloads it, and the ID card until it's in Wallet.
  def change do
    alter table(:tax_credit_letters) do
      add :downloaded_at, :utc_datetime_usec
    end

    alter table(:member_cards) do
      add :in_wallet_at, :utc_datetime_usec
    end
  end
end
