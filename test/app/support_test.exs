defmodule App.SupportTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures

  test "the site admins are the admin users, named by their member, else by email" do
    team = team_fixture()
    AccountsFixtures.user_fixture(%{email: "riley.okafor@example.com", is_admin: true})
    AccountsFixtures.user_fixture(%{email: "Jordan.Lee@example.com", is_admin: true})
    AccountsFixtures.user_fixture(%{email: "cameron.ruiz@example.com"})
    member_fixture(team, %{name: "Jordan Lee", email: "jordan.lee@example.com"})

    assert App.Support.site_admins() == [
             %{name: "Jordan Lee", email: "jordan.lee@example.com"},
             %{name: "riley.okafor@example.com", email: "riley.okafor@example.com"}
           ]
  end

  test "with no admins, the support address stands in" do
    assert App.Support.site_admins() == [
             %{name: "SAR Duty site admins", email: "support@sarduty.com"}
           ]
  end
end
