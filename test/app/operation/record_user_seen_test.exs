defmodule App.Operation.RecordUserSeenTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Operation.RecordUserSeen

  @now ~U[2026-09-14 12:00:00Z]

  test "records a user never seen before" do
    assert RecordUserSeen.due?(%User{last_seen_at: nil}, @now)
  end

  test "records again once an hour has passed" do
    assert RecordUserSeen.due?(%User{last_seen_at: ~U[2026-09-14 11:00:00Z]}, @now)
  end

  test "skips a user seen within the hour" do
    refute RecordUserSeen.due?(%User{last_seen_at: ~U[2026-09-14 11:00:01Z]}, @now)
  end

  test "never records an admin" do
    refute RecordUserSeen.due?(%User{is_admin: true, last_seen_at: nil}, @now)
  end
end
