defmodule App.Repo.Migrations.RemovePassTestAtFromMemberCards do
  use Ecto.Migration

  # Send test update is gone; nothing reads when a card was last tested.
  def change do
    alter table(:member_cards) do
      remove :pass_test_at, :utc_datetime_usec
    end
  end
end
