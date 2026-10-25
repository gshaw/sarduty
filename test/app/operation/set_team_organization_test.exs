defmodule App.Operation.SetTeamOrganizationTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.Team
  alias App.Model.TeamLoginGrant
  alias App.Operation.SetTeamOrganization
  alias App.Worker.PushPassUpdatesWorker

  setup do
    team = team_fixture(%{name: "Coast Range SAR"})
    manager_fixture(team, %{email: "owner@example.com"})
    manager_fixture(team, %{email: "Owner@example.com", d4h_permission: 1})
    TeamLoginGrant.grant!(team, "office@example.com", "office")

    organization =
      organization_fixture([], %{
        name: "Western SAR Association",
        short_name: "WSARA",
        primary_hours_tag: "WSARA Primary"
      })

    %{team: team, organization: organization, admin: user_fixture(%{is_admin: true})}
  end

  defp events(kind), do: Event |> where([e], e.kind == ^kind) |> Repo.all()

  test "adding sets the organization, queues its passes, records it, and emails each team admin",
       %{team: team, organization: organization, admin: admin} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %Team{organization_id: id}} =
               SetTeamOrganization.call(team, organization, admin)

      assert id == organization.id
      assert_enqueued(worker: PushPassUpdatesWorker, args: %{team_id: team.id})
    end)

    assert [event] = events(:organization_team_added)
    assert event.team_id == team.id
    assert event.user_id == admin.id
    assert event.data["organization_id"] == organization.id

    # One email per team admin: the two D4H rows share an email.
    for to <- ["office@example.com", "owner@example.com"] do
      assert_received {:email,
                       %{to: [{"", ^to}], subject: "Coast Range SAR is now in WSARA"} = email}

      assert email.reply_to == {"", "support@sarduty.com"}
      assert email.text_body =~ "count WSARA's hours tags: WSARA Primary (primary hours)."

      assert email.text_body =~
               "Your team keeps its own tags for secondary hours and other hours."
    end

    refute_received {:email, _email}
  end

  test "a team in another organization can't be added, so two adds can't race",
       %{team: team, organization: organization, admin: admin} do
    other = organization_fixture([team])
    assert SetTeamOrganization.call(team, organization, admin) == {:error, :taken}
    assert Repo.reload!(team).organization_id == other.id
  end

  test "a team whose own tag would repeat the organization's is refused",
       %{team: team, organization: organization, admin: admin} do
    team = team |> Ecto.Changeset.change(secondary_hours_tag: "WSARA Primary") |> Repo.update!()

    assert {:error, {:hours_tag, text}} = SetTeamOrganization.call(team, organization, admin)
    assert text =~ "Coast Range SAR's own tag for secondary hours repeats one of WSARA's."
    assert Repo.reload!(team).organization_id == nil
  end

  test "removing leaves its ID cards as they are and emails its team admins",
       %{team: team, organization: organization, admin: admin} do
    {:ok, team} = SetTeamOrganization.call(team, organization, admin)
    flush_emails()

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %Team{organization_id: nil, id_cards_enabled: true}} =
               SetTeamOrganization.call(team, nil, admin)

      assert_enqueued(worker: PushPassUpdatesWorker, args: %{team_id: team.id})
    end)

    assert [_event] = events(:organization_team_removed)
    assert_received {:email, %{subject: "Coast Range SAR is no longer in WSARA"} = email}
    assert email.text_body =~ "Your ID cards stay on or off as they are."
  end

  test "only a SAR Duty admin adds or removes a team", %{team: team, organization: organization} do
    user = user_fixture()
    assert SetTeamOrganization.call(team, organization, user) == {:error, :forbidden}
    assert SetTeamOrganization.call(team, nil, user) == {:error, :forbidden}
  end

  test "a team with no team admins gets no email", %{organization: organization, admin: admin} do
    {:ok, _team} = SetTeamOrganization.call(team_fixture(), organization, admin)
    refute_received {:email, _email}
  end

  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
