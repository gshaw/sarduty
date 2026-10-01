defmodule App.Repo.Migrations.AddPassFetchedAtToMemberCards do
  use Ecto.Migration

  # When a phone last fetched the card's Apple pass, and when a manager last sent a test
  # update. Both nil until it happens.
  def change do
    alter table(:member_cards) do
      add :pass_fetched_at, :utc_datetime_usec
      add :pass_test_at, :utc_datetime_usec
    end
  end
end
