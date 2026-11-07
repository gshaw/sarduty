defmodule App.Operation.IssueEveryMemberCardTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Operation.IssueEveryMemberCard

  defp member(name, email), do: %Member{name: name, email: email}

  test "the confirm's counts: cards for all, email for those with an address" do
    members = [
      member("Avery Chen", "avery@example.com"),
      member("Eli Haddad", nil),
      member("Quinn Laval", ""),
      member("Riley Okafor", "riley@example.com")
    ]

    assert IssueEveryMemberCard.plan(members) == %{cards: 4, emails: 2, no_email: 2}
    assert IssueEveryMemberCard.plan([]) == %{cards: 0, emails: 0, no_email: 0}
  end
end
