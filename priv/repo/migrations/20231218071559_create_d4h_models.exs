defmodule App.Repo.Migrations.CreateD4HModels do
  use Ecto.Migration

  def change do
    create table(:activities) do
      add :team_id, references(:teams), null: false
      add :d4h_id, :integer, null: false
      add :ref_id, :string
      add :is_published, :boolean, null: false
      add :title, :string, null: false
      add :description, :string
      add :activity_kind, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec, null: false
      add :address, :string
      add :coordinate, :string
      add :hours_kind, :string
      add :tags, {:array, :string}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:members) do
      add :team_id, references(:teams), null: false
      add :d4h_id, :integer, null: false
      add :ref_id, :string
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      add :address, :string
      add :coordinate, :string
      add :position, :string
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:attendances) do
      add :member_id, references(:members), null: false
      add :activity_id, references(:activities), null: false
      add :d4h_id, :integer, null: false
      add :duration_in_minutes, :integer, null: false
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :status, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
