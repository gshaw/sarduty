defmodule App.Repo.Migrations.CreateTransfers do
  use Ecto.Migration

  # A transfer (#892): a copy of a member's awards and certificates that a team admin at
  # another team adds with a one-time code. The awards are copied from the sending team's
  # D4H when the code is made; the files sit in their own table, so lists never load
  # them, and are deleted once the code is used, cancelled, or expires.
  def change do
    create table(:transfers) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :made_by_user_id, references(:users, on_delete: :nilify_all)
      # Encrypted, so the sending team's page can show it again, and hashed for lookup.
      add :code, :string, null: false
      add :code_hash, :string, null: false
      # Who it is for, as the sending team had them, for the receiving team.
      add :member_name, :string, null: false
      add :member_email, :string
      add :expires_at, :utc_datetime_usec, null: false
      add :cancelled_at, :utc_datetime_usec
      add :cancelled_by_user_id, references(:users, on_delete: :nilify_all)
      add :used_at, :utc_datetime_usec
      add :used_by_team_id, references(:teams, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:transfers, [:code_hash])
    create index(:transfers, [:team_id])
    create index(:transfers, [:member_id])
    create index(:transfers, [:used_by_team_id])

    # team_id too, the sending team's, so every query and the team purge scope it.
    create table(:transfer_awards) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :transfer_id, references(:transfers, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :qualification_title, :string, null: false
      add :d4h_qualification_id, :integer, null: false
      add :organization_owned, :boolean, null: false, default: false
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      # Its certificate, while the copy is kept; nil when the award had none.
      add :file_name, :string
      add :content_type, :string
      add :file_size, :integer
    end

    create index(:transfer_awards, [:transfer_id])
    create index(:transfer_awards, [:team_id])

    create table(:transfer_award_files) do
      add :transfer_award_id, references(:transfer_awards, on_delete: :delete_all), null: false

      add :bytes, :binary, null: false
    end

    create unique_index(:transfer_award_files, [:transfer_award_id])
  end
end
