defmodule App.Model.TransferTest do
  use ExUnit.Case, async: true

  alias App.Model.Transfer

  @now ~U[2026-11-05 12:00:00Z]

  describe "status/2" do
    test "open until it expires, then expired" do
      transfer = %Transfer{expires_at: Transfer.expires_at(@now)}

      assert Transfer.status(transfer, @now) == :open
      assert Transfer.status(transfer, DateTime.add(@now, 30, :day)) == :expired
      assert Transfer.expires_at(@now) == ~U[2026-12-05 12:00:00Z]
    end

    test "used or cancelled, whatever the date" do
      transfer = %Transfer{expires_at: DateTime.add(@now, -1, :day)}

      assert Transfer.status(%{transfer | used_at: @now}, @now) == :used
      assert Transfer.status(%{transfer | cancelled_at: @now}, @now) == :cancelled
    end
  end

  describe "code_hash/1" do
    test "case, spaces, and the dash don't matter" do
      hash = Transfer.code_hash("K7QM4XRD")

      assert is_binary(hash)
      assert Transfer.code_hash("k7qm-4xrd") == hash
      assert Transfer.code_hash(" K7QM 4XRD ") == hash
      refute Transfer.code_hash("K7QM4XRE") == hash
    end

    test "nil for what can't be a code" do
      assert Transfer.code_hash("K7QM") == nil
      assert Transfer.code_hash("K7QM-4XR0") == nil
      assert Transfer.code_hash(nil) == nil
    end
  end

  test "format_code/1 adds the dash" do
    assert Transfer.format_code(%Transfer{code: "K7QM4XRD"}) == "K7QM-4XRD"
  end
end
