defmodule App.Repo.Migrations.AddEmailStatusToMemberCards do
  use Ecto.Migration

  # Issue, Replace, and Email card queue a job (#893), so each card keeps whether its
  # email went, and when. expires_at is when its passes expire: it rolls while the card
  # is active and stays put once it isn't, so Wallet shows a former member's pass expired.
  def change do
    alter table(:member_cards) do
      add :email_status, :string
      add :emailed_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
    end
  end
end
