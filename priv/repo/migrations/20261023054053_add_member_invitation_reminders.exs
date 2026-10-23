defmodule App.Repo.Migrations.AddMemberInvitationReminders do
  use Ecto.Migration

  # Whether team admins can email the member a reminder about an activity they haven't
  # replied to (#444). On the member, not the login: most members get email without
  # ever logging in. Set in SAR Duty, never from D4H.
  def change do
    alter table(:members) do
      add :invitation_reminders, :boolean, null: false, default: true
    end
  end
end
