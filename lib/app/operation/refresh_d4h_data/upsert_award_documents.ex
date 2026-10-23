defmodule App.Operation.RefreshD4HData.UpsertAwardDocuments do
  @moduledoc """
  Notes which awards have a certificate in D4H (#314): the document attached to the
  award. Pages link to it and SAR Duty fetches the file when someone opens it, so no
  file is stored here. Runs after the awards, in the refresh and in the sync.
  """

  alias App.Adapter.D4H
  alias App.Model.MemberQualificationAward

  require Logger

  def call(d4h, team) do
    documents = D4H.fetch_award_documents(d4h)
    changes = changes(MemberQualificationAward.document_ids(team.id), documents)
    MemberQualificationAward.set_documents(changes)
    Logger.info("Set #{length(changes)} award certificates for team #{team.id}")
    length(changes)
  end

  @doc """
  The awards whose certificate changed, as `[{id, d4h_document_id or nil}]`. `awards`
  are `{id, d4h_award_id, d4h_document_id}`. An award with several documents takes the
  newest, the one with the highest id.
  """
  def changes(awards, documents) do
    newest =
      documents
      |> Enum.group_by(& &1.d4h_target_id, & &1.d4h_document_id)
      |> Map.new(fn {award_id, ids} -> {award_id, Enum.max(ids)} end)

    Enum.flat_map(awards, fn {id, d4h_award_id, current} ->
      wanted = Map.get(newest, d4h_award_id)
      if wanted == current, do: [], else: [{id, wanted}]
    end)
  end
end
