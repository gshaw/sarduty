defmodule App.Model.ShortLinkTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.ShortLink

  @now ~U[2026-10-10 12:00:00.000000Z]

  test "codes are 8 lowercase characters with no characters that look alike" do
    for _ <- 1..200 do
      code = ShortLink.generate_code()
      assert code =~ ShortLink.code_format()
      refute code =~ ~r/[0o1li]/
    end
  end

  test "a link is found by its code until it expires" do
    link = ShortLink.create!("/attendance/abc", expires_at: DateTime.add(@now, 1, :hour))

    assert ShortLink.find_by_code(link.code, @now).target == "/attendance/abc"
    refute ShortLink.find_by_code(link.code, DateTime.add(@now, 2, :hour))
    refute ShortLink.find_by_code("zzzzzzzz", @now)
  end

  test "a link with no expiry never expires" do
    link = ShortLink.create!("/somewhere")
    assert ShortLink.find_by_code(link.code, ~U[2099-01-01 00:00:00Z])
  end

  test "the target must be a path on this site" do
    assert_raise ArgumentError, fn -> ShortLink.create!("https://example.com") end
    assert_raise ArgumentError, fn -> ShortLink.create!("//example.com") end
  end

  test "deleting only touches the team's own links" do
    team = team_fixture()
    other = team_fixture()
    mine = ShortLink.create!("/a", team_id: team.id)
    theirs = ShortLink.create!("/b", team_id: other.id)

    ShortLink.delete_all!(team, [mine.id, theirs.id])

    refute Repo.get(ShortLink, mine.id)
    assert Repo.get(ShortLink, theirs.id)
  end
end
