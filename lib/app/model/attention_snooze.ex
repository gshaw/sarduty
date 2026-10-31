defmodule App.Model.AttentionSnooze do
  use App, :model

  alias App.Accounts.User
  alias App.Model.AttentionSnooze
  alias App.Model.Team
  alias App.Repo

  # A team admin's snooze of a Needs attention item (#751): hidden for every team admin
  # until `until`, or until someone not in `ids` turns up behind it. Needs attention stays
  # computed, so this is the only thing stored. `key` is the item's key as a string.
  schema "attention_snoozes" do
    belongs_to :team, Team
    belongs_to :user, User
    field :key, :string
    field :ids, {:array, :integer}
    field :until, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc "The team's snoozes, with who made them."
  def get_all(%Team{} = team) do
    AttentionSnooze
    |> where([s], s.team_id == ^team.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Snoozes the item for the team. Snoozing it again replaces the last snooze."
  def put!(%Team{} = team, %User{} = user, key, ids, until) do
    Repo.insert!(
      %AttentionSnooze{team_id: team.id, user_id: user.id, key: key, ids: ids, until: until},
      on_conflict: {:replace, [:user_id, :ids, :until, :updated_at]},
      conflict_target: [:team_id, :key]
    )
  end

  @doc "Ends the team's snooze of the item, if any."
  def delete(%Team{} = team, key) do
    {count, _} =
      AttentionSnooze
      |> where([s], s.team_id == ^team.id and s.key == ^key)
      |> Repo.delete_all()

    count
  end

  @doc "Deletes snoozes that ended more than a day ago. Returns how many."
  def prune(now) do
    cutoff = DateTime.add(now, -1, :day)
    {count, _} = AttentionSnooze |> where([s], s.until < ^cutoff) |> Repo.delete_all()
    count
  end
end
