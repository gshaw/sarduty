defmodule App.Operation.SnoozeAttentionItemTest do
  use ExUnit.Case, async: true

  alias App.Operation.SnoozeAttentionItem

  @now ~U[2026-10-30 16:00:00.123456Z]

  @items [
    %{key: :retiring, ids: [9, 4], title: "2 retiring members hold 3 items"},
    %{key: :retiring_access, title: "1 retiring member can still log in to D4H"}
  ]

  test "takes the item's members, sorted, from the item itself" do
    assert {:ok, %{ids: [4, 9]}} = SnoozeAttentionItem.plan(@items, "retiring", :week, @now)
  end

  test "lasts a day, a week, or a calendar month" do
    until = fn period ->
      {:ok, %{until: until}} = SnoozeAttentionItem.plan(@items, "retiring", period, @now)
      until
    end

    assert until.(:day) == ~U[2026-10-31 16:00:00Z]
    assert until.(:week) == ~U[2026-11-06 16:00:00Z]
    assert until.(:month) == ~U[2026-11-30 16:00:00Z]
  end

  test "refuses an item without members, and one that is gone" do
    assert SnoozeAttentionItem.plan(@items, "retiring_access", :week, @now) ==
             {:error, :not_found}

    assert SnoozeAttentionItem.plan(@items, "drafts", :week, @now) == {:error, :not_found}
  end
end
