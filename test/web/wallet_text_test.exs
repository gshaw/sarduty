defmodule Web.WalletTextTest do
  use ExUnit.Case, async: true

  alias App.Model.MemberCard
  alias Web.WalletText

  @saved ~U[2026-11-07 20:00:00.000000Z]

  # Every line the card's page can show (#952): Apple's devices, and Google's mark.
  for {devices, in_wallet_at, line} <- [
        {0, nil, "SAR Duty doesn't see your ID card in Wallet yet."},
        {1, nil, "SAR Duty sees your ID card in Apple Wallet on 1 device."},
        {2, nil, "SAR Duty sees your ID card in Apple Wallet on 2 devices."},
        {0, @saved, "SAR Duty sees your ID card in Google Wallet."},
        {2, @saved,
         "SAR Duty sees your ID card in Apple Wallet on 2 devices and in Google Wallet."}
      ] do
    test "seen/2: #{line}" do
      card = %MemberCard{in_wallet_at: unquote(Macro.escape(in_wallet_at))}
      assert WalletText.seen(unquote(devices), card) == unquote(line)
    end
  end

  test "summary/3 puts both on one line for the ID Card tab" do
    assert WalletText.summary(0, %MemberCard{}, "America/Vancouver") == "Not in Wallet yet"

    assert WalletText.summary(1, %MemberCard{in_wallet_at: @saved}, "America/Vancouver") ==
             "In Apple Wallet on 1 device · In Google Wallet"
  end
end
