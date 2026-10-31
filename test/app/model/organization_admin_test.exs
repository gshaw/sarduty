defmodule App.Model.OrganizationAdminTest do
  use App.DataCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.OrganizationAdmin

  defp events(kind), do: Event |> where([e], e.kind == ^kind) |> Repo.all()

  setup do
    %{organization: organization_fixture(), admin: user_fixture(%{is_admin: true})}
  end

  test "a SAR Duty admin adds one, stored lowercase, with an event naming who acted",
       %{organization: organization, admin: admin} do
    assert {:ok, added} =
             OrganizationAdmin.add(
               organization,
               %{email: " Dana@WSARA.example.org ", reason: "Office manager"},
               admin
             )

    assert added.email == "dana@wsara.example.org"
    assert added.added_by_user_id == admin.id
    assert [event] = events(:organization_admin_added)
    assert event.user_id == admin.id
    assert event.data["organization_id"] == organization.id
    assert event.data["who"] == Event.who("dana@wsara.example.org")
    refute inspect(event.data) =~ "dana"
  end

  test "a bad email, a repeat, or a SAR Duty admin's email is a field error",
       %{organization: organization, admin: admin} do
    assert {:error, changeset} = OrganizationAdmin.add(organization, %{email: "dana"}, admin)
    assert %{email: ["Enter an email like name@example.com."]} = errors_on(changeset)

    {:ok, _added} = OrganizationAdmin.add(organization, %{email: "dana@example.org"}, admin)

    assert {:error, changeset} =
             OrganizationAdmin.add(organization, %{email: "DANA@example.org"}, admin)

    assert %{email: ["This email is an organization admin already."]} = errors_on(changeset)

    assert {:error, changeset} = OrganizationAdmin.add(organization, %{email: admin.email}, admin)

    assert %{email: ["Enter someone who is not a SAR Duty site admin." <> _rest]} =
             errors_on(changeset)
  end

  test "only a SAR Duty admin adds or removes one", %{organization: organization} do
    row = organization_admin_fixture(organization, "dana@example.org")
    dana = user_fixture(%{email: "dana@example.org"})

    assert OrganizationAdmin.add(organization, %{email: "other@example.org"}, dana) ==
             {:error, :forbidden}

    assert OrganizationAdmin.remove(organization, row.id, dana) == {:error, :forbidden}
    assert OrganizationAdmin.admin_of?(organization.id, dana)
  end

  test "removing is scoped to the organization and records an event",
       %{organization: organization, admin: admin} do
    other = organization_fixture()
    row = organization_admin_fixture(other, "dana@example.org")

    assert OrganizationAdmin.remove(organization, row.id, admin) == {:error, :not_found}
    assert {:ok, _removed} = OrganizationAdmin.remove(other, row.id, admin)
    assert OrganizationAdmin.get_for_organization(other) == []
    assert [_event] = events(:organization_admin_removed)
  end

  test "Last seen is stamped at most hourly, and only for its admins",
       %{organization: organization} do
    organization_admin_fixture(organization, "dana@example.org")
    dana = user_fixture(%{email: "Dana@example.org"})
    now = ~U[2026-10-24 12:00:00Z]

    OrganizationAdmin.record_seen(organization.id, dana, now)

    assert [%{last_seen_at: ~U[2026-10-24 12:00:00Z]}] =
             OrganizationAdmin.get_for_organization(organization)

    OrganizationAdmin.record_seen(organization.id, dana, DateTime.add(now, 30, :minute))

    assert [%{last_seen_at: ~U[2026-10-24 12:00:00Z]}] =
             OrganizationAdmin.get_for_organization(organization)

    OrganizationAdmin.record_seen(organization.id, dana, DateTime.add(now, 61, :minute))

    assert [%{last_seen_at: ~U[2026-10-24 13:01:00Z]}] =
             OrganizationAdmin.get_for_organization(organization)

    assert Repo.reload!(dana).last_seen_at == nil
  end

  test "organizations_for_email/1 lists the organizations they are an admin of" do
    a = organization_fixture([], %{name: "B Association"})
    b = organization_fixture([], %{name: "A Association"})
    organization_fixture()
    organization_admin_fixture(a, "dana@example.org")
    organization_admin_fixture(b, "dana@example.org")

    assert "DANA@example.org" |> OrganizationAdmin.organizations_for_email() |> Enum.map(& &1.id) ==
             [b.id, a.id]
  end
end
