defmodule App.Operation.SignUpTeamTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H
  alias App.Operation.SignUpTeam

  @now ~U[2026-10-04 12:00:00Z]
  @d4h_team %D4H.Team{name: "Ridge SAR"}

  defp member(attrs) do
    struct(
      %D4H.Member{
        d4h_member_id: 1,
        email: "pat@example.com",
        permission: 0,
        status: "OPERATIONAL"
      },
      attrs
    )
  end

  defp check(email, members, existing \\ nil),
    do: SignUpTeam.check(email, @d4h_team, members, existing, @now)

  test "an Owner or Editor at that email may sign the team up, in any letter case" do
    assert {:ok, %{d4h_member_id: 1}} = check(" Pat@Example.com ", [member(%{})])
    assert {:ok, _} = check("pat@example.com", [member(%{permission: 1})])
  end

  test "a member who isn't an Owner or Editor may not" do
    assert {:error, {:email, message}} = check("pat@example.com", [member(%{permission: 2})])
    assert message =~ "Owner or Editor of Ridge SAR"
  end

  test "a retired or departed manager may not" do
    assert {:error, {:email, _}} = check("pat@example.com", [member(%{status: "RETIRED"})])

    left = member(%{left_at: ~U[2026-01-01 00:00:00Z]})
    assert {:error, {:email, _}} = check("pat@example.com", [left])
  end

  test "an email no member has may not" do
    assert {:error, {:email, message}} = check("stranger@example.com", [member(%{})])
    assert message =~ "No member of"
  end

  test "a team already on SAR Duty can't sign up again" do
    assert {:error, {:access_key, message}} =
             check("pat@example.com", [member(%{})], %App.Model.Team{})

    assert message =~ "already on SAR Duty"
  end
end
