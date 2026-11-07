defmodule Web.WalletText do
  @moduledoc """
  What SAR Duty knows of a card's Wallets, in words: the ID Card tab's Wallet row and the
  card's page say the same (#952). `phones` is how many devices hold the Apple pass,
  where an iPhone and its paired Apple Watch count as 2
  (`PassRegistration.count_holding/1`); Google's mark is `in_wallet_at`. Only the tab
  gives the count: the card's page says whether, since iCloud carries the pass to a
  member's iPad too and a member reads 2 as a mistake.
  """
  alias App.Model.MemberCard

  @doc "The Apple pass's phones and last download, or nil when no phone holds it."
  def apple(0, %MemberCard{}, _timezone), do: nil

  def apple(phones, %MemberCard{} = card, timezone) do
    on = "In Apple Wallet on #{Service.Format.count(phones, one: "1 device", many: "%d devices")}"

    case card.pass_fetched_at do
      nil ->
        on

      fetched_at ->
        "#{on} · last downloaded #{Service.Format.month_day_time(fetched_at, timezone)}"
    end
  end

  @doc "In Google Wallet, or nil when Google hasn't said it was saved."
  def google(%MemberCard{in_wallet_at: nil}), do: nil
  def google(%MemberCard{}), do: "In Google Wallet"

  @doc """
  What SAR Duty sees, as one sentence for the card's page, with no count: "SAR Duty sees
  your ID card in Apple Wallet."
  """
  def seen(phones, %MemberCard{} = card) do
    apple = if phones > 0, do: "Apple Wallet"

    google = if card.in_wallet_at, do: "Google Wallet"

    case Enum.reject([apple, google], &is_nil/1) do
      [] -> "SAR Duty doesn't see your ID card in Wallet yet."
      wallets -> "SAR Duty sees your ID card in #{Enum.join(wallets, " and in ")}."
    end
  end

  @doc "Both on one line, for the ID Card tab."
  def summary(phones, %MemberCard{} = card, timezone) do
    case Enum.reject([apple(phones, card, timezone), google(card)], &is_nil/1) do
      [] -> "Not in Wallet yet"
      parts -> Enum.join(parts, " · ")
    end
  end
end
