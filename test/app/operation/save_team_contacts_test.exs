defmodule App.Operation.SaveTeamContactsTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Member
  alias App.Operation.SaveTeamContacts

  @now ~U[2026-10-31 19:00:00Z]

  test "saves one or two of the team's members, any of them, not only team admins" do
    team = team_fixture()
    sam = member_fixture(team, %{name: "Sam Rivera"})
    alex = manager_fixture(team, %{name: "Alex Chen"})

    assert {:ok, team} =
             SaveTeamContacts.call(
               team,
               %{"first_contact_id" => sam.id, "second_contact_id" => alex.id},
               @now
             )

    assert team |> Member.get_team_contacts(@now) |> Enum.map(& &1.name) == [
             "Sam Rivera",
             "Alex Chen"
           ]
  end

  test "refuses someone on another team, and the same person twice" do
    team = team_fixture()
    sam = member_fixture(team)
    other = member_fixture(team_fixture())

    assert {:error, changeset} =
             SaveTeamContacts.call(team, %{"first_contact_id" => other.id}, @now)

    assert {"Select a member.", _} = changeset.errors[:first_contact_id]

    assert {:error, changeset} =
             SaveTeamContacts.call(
               team,
               %{"first_contact_id" => sam.id, "second_contact_id" => sam.id},
               @now
             )

    assert {"Select someone else, or None.", _} = changeset.errors[:second_contact_id]
  end

  test "a contact who leaves or has no email drops off, so the team is asked again" do
    team = team_fixture()
    gone = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    no_email = member_fixture(team, %{email: nil})

    team =
      team
      |> Ecto.Changeset.change(first_contact_id: gone.id, second_contact_id: no_email.id)
      |> App.Repo.update!()

    assert Member.get_team_contacts(team, @now) == []
    refute gone.id in (team |> SaveTeamContacts.choices(@now) |> Enum.map(& &1.id))
  end
end
