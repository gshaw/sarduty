defmodule App.Repo.Migrations.AddSerialNumberToMemberCards do
  use Ecto.Migration

  # A replacement card keeps its member's Apple Wallet serial number, so Wallet updates
  # the pass in place instead of adding a second one. Cards made before this keep the
  # serial their passes already carry.
  def up do
    alter table(:member_cards) do
      add :serial_number, :string
    end

    flush()
    execute "UPDATE member_cards SET serial_number = 'member-card-' || id"
    create index(:member_cards, [:serial_number])
  end

  def down do
    drop index(:member_cards, [:serial_number])

    alter table(:member_cards) do
      remove :serial_number
    end
  end
end
