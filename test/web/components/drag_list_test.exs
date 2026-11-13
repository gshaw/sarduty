defmodule Web.Components.DragListTest do
  use ExUnit.Case, async: true

  alias Web.Components.DragList

  @rows [%{id: 1}, %{id: 2}, %{id: 3}]
  defp key(row), do: to_string(row.id)

  test "puts the rows in the order of the keys" do
    assert DragList.reorder(@rows, ["3", "1", "2"], &key/1) ==
             {:ok, [%{id: 3}, %{id: 1}, %{id: 2}]}
  end

  test "keys that don't name each row once change nothing" do
    assert DragList.reorder(@rows, ["3", "1"], &key/1) == :error
    assert DragList.reorder(@rows, ["3", "1", "1"], &key/1) == :error
    assert DragList.reorder(@rows, ["3", "1", "4"], &key/1) == :error
    assert DragList.reorder(@rows, nil, &key/1) == :error
  end
end
