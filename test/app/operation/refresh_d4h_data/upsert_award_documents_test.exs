defmodule App.Operation.RefreshD4HData.UpsertAwardDocumentsTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.Document
  alias App.Operation.RefreshD4HData.UpsertAwardDocuments

  defp document(id, award_id), do: %Document{d4h_document_id: id, d4h_target_id: award_id}

  test "sets the newest document, clears one D4H dropped, and leaves the rest" do
    awards = [
      {1, 101, nil},
      {2, 102, 7},
      {3, 103, 8},
      {4, 104, nil},
      {5, 105, 9}
    ]

    documents = [document(20, 101), document(21, 101), document(8, 103), document(30, 999)]

    assert UpsertAwardDocuments.changes(awards, documents) == [{1, 21}, {2, nil}, {5, nil}]
  end
end
