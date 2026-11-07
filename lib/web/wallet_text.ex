defmodule Web.WalletText do
  @moduledoc """
  What SAR Duty knows of a card's Wallets, in words: the ID Card tab's Wallet row and the
  card's page say the same (#952). `phones` is how many phones registered the Apple pass
  (`PassRegistration.count_holding/1`); Google's mark is `in_wallet_at`.
  """
  alias App.Model.MemberCard

  @doc "The Apple pass's phones and last download, or nil when no phone holds it."
  def apple(0, %MemberCard{}, _timezone), do: nil

  def apple(phones, %MemberCard{} = card, timezone) do
    on = "In Apple Wallet on #{Service.Format.count(phones, one: "1 phone", many: "%d phones")}"

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
  What SAR Duty sees, as one sentence for the card's page: "SAR Duty sees your ID card in
  Apple Wallet on 1 phone."
  """
  def seen(phones, %MemberCard{} = card) do
    apple =
      if phones > 0,
        do: "Apple Wallet on #{Service.Format.count(phones, one: "1 phone", many: "%d phones")}"

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
