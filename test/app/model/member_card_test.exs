defmodule App.Model.MemberCardTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.MemberCard

  @now ~U[2026-09-30 12:00:00Z]

  test "generate_code makes 8 characters that normalize to themselves" do
    for _ <- 1..200 do
      code = MemberCard.generate_code()
      assert String.length(code) == 8
      assert MemberCard.normalize_code(code) == code
    end
  end

  test "format_code puts a dash in the middle" do
    assert MemberCard.format_code("K7Q4M2XA") == "K7Q4-M2XA"
  end

  test "normalize_code ignores case, spaces, and dashes" do
    assert MemberCard.normalize_code(" k7q4-m2xa ") == "K7Q4M2XA"
    assert MemberCard.normalize_code("K7Q4 M2XA") == "K7Q4M2XA"
    assert MemberCard.normalize_code("AAAAAAAA") == "AAAAAAAA"
  end

  test "normalize_code rejects what can't be a code" do
    assert MemberCard.normalize_code("K7Q4M2X") == nil
    assert MemberCard.normalize_code("K7Q4M2XAB") == nil
    assert MemberCard.normalize_code("K7Q4M2X0") == nil
    assert MemberCard.normalize_code("https://evil.example/K7Q4M2XA") == nil
    assert MemberCard.normalize_code(nil) == nil
  end

  test "status is active for a current member, inactive once they leave, revoked when cancelled" do
    current = %Member{left_at: nil}
    left = %Member{left_at: ~U[2026-01-01 00:00:00Z]}

    assert MemberCard.status(%MemberCard{member: current}, @now) == :active
    assert MemberCard.status(%MemberCard{member: left}, @now) == :inactive
    assert MemberCard.status(%MemberCard{member: current, revoked_at: @now}, @now) == :revoked
  end
end
