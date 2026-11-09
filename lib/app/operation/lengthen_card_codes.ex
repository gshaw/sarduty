defmodule App.Operation.LengthenCardCodes do
  @moduledoc """
  Moves every live card from an 8-character code to a 10-character one (#969), once,
  after the deploy that lengthened codes: `bin/sarduty rpc
  "App.Operation.LengthenCardCodes.call()"`. Each card keeps its row, serial, and token,
  so its Apple and Google passes update in place: the push job for each team rebuilds the
  passes, and their fingerprints changed with the code. The old code then matches no
  card. Safe to run again: it only finds cards still on an old code.

  Remove this, and MemberCard.get_all_with_old_codes/0 and lengthen_code!/1, once it has
  run in production.
  """

  alias App.Model.MemberCard
  alias App.Repo
  alias App.Worker.PushPassUpdatesWorker

  @doc "Returns how many cards it moved."
  def call do
    cards = MemberCard.get_all_with_old_codes()

    Repo.transaction(fn ->
      Enum.each(cards, &MemberCard.lengthen_code!/1)
      cards |> Enum.map(& &1.team_id) |> Enum.uniq() |> PushPassUpdatesWorker.enqueue_team_ids()
    end)

    length(cards)
  end
end
