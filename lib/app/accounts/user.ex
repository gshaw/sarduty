defmodule App.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias App.Accounts.User
  alias App.Repo

  # A person who logs in with an emailed link. Which teams they reach comes from D4H
  # (#57): see App.Model.Team.get_managed_by/2.
  schema "users" do
    field :email, :string
    field :confirmed_at, :naive_datetime
    field :is_admin, :boolean, default: false
    # When the user last opened a team page, to the hour. See App.Operation.RecordUserSeen.
    field :last_seen_at, :utc_datetime
    # The team they last opened; logging in lands there. See App.Operation.RecordUserSeen.
    field :last_team_id, :integer

    timestamps(type: :utc_datetime)
  end

  def get!(id), do: Repo.get!(User, id)

  @doc "A new user for an email that may log in. Emails are stored lowercase."
  def new_changeset(attrs) do
    %User{}
    |> cast(attrs, [:email])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "Enter an email with an @ sign and no spaces."
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  @doc "Marks the email as proven, the first time a login link is used."
  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, confirmed_at: user.confirmed_at || now)
  end
end
