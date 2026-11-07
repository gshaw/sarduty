defmodule App.Operation.CheckGoogleWalletSave do
  @moduledoc """
  Asks Google whether a card's pass was saved, while its page waits after a tap on Add
  to Google Wallet (#952). Google's save callback says the same, but only reaches
  production, and may come after the member is back on the page. A save marks the card
  in Wallet, which broadcasts `:wallet_changed`, as the callback does. It never clears
  the mark: `hasUsers` may stay true after a delete, and the delete callback clears it.
  """

  alias App.Adapter.GoogleWallet
  alias App.Model.MemberCard
  alias App.Operation.BuildGooglePass

  @doc "`:saved`, `:not_saved`, or `{:error, reason}`."
  def call(%MemberCard{} = card, now) do
    if BuildGooglePass.configured?() do
      config = BuildGooglePass.config()

      with {:ok, token} <- GoogleWallet.access_token(config.credentials, now),
           {:ok, saved?} <-
             GoogleWallet.has_users?(token, BuildGooglePass.object_id(card, config)) do
        record(card, saved?, now)
      end
    else
      {:error, :not_configured}
    end
  end

  defp record(_card, false, _now), do: :not_saved

  defp record(card, true, now) do
    if !card.in_wallet_at, do: MemberCard.mark_in_wallet!(card, now)
    :saved
  end
end
