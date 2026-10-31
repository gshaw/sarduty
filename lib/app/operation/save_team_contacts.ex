defmodule App.Operation.SaveTeamContacts do
  @moduledoc """
  Saves the team's contacts (#780) from Team settings › Team admins: one or two of its
  members, who need not be team admins. Get help sends the team's messages to them.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}` or `{:error, changeset}`."
  def call(%Team{} = team, params, now \\ DateTime.utc_now()) do
    allowed = team |> choices(now) |> MapSet.new(& &1.id)

    team
    |> Team.build_contacts_changeset(params)
    |> check(allowed)
    |> Repo.update()
  end

  @doc "The members a team admin can pick: those SAR Duty counts with an email, by name."
  def choices(%Team{} = team, now) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> where([m], not is_nil(m.email) and m.email != "")
    |> Member.current_query(now)
    |> Member.counted_query()
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  @doc "Pure. Each pick is one of `allowed`, the member ids, and the two are not the same."
  def check(changeset, allowed) do
    first = get_field(changeset, :first_contact_id)
    second = get_field(changeset, :second_contact_id)

    changeset
    |> check_allowed(:first_contact_id, allowed)
    |> check_allowed(:second_contact_id, allowed)
    |> then(fn changeset ->
      if first && first == second,
        do: add_error(changeset, :second_contact_id, "Select someone else, or None."),
        else: changeset
    end)
  end

  defp check_allowed(changeset, field, allowed) do
    case get_change(changeset, field) do
      nil -> changeset
      id -> if id in allowed, do: changeset, else: add_error(changeset, field, "Select a member.")
    end
  end
end
