defmodule Service.Phone do
  @moduledoc """
  Phone numbers as D4H and people type them, turned into E.164 ("+16045551234") so two
  spellings of one number match. Without a country code a number is North American.
  """

  @doc """
  The number in E.164, or nil when it isn't one. Drops an extension ("x12", "ext. 12")
  and every separator.
  """
  def normalize(nil), do: nil

  def normalize(text) when is_binary(text) do
    text = text |> String.downcase() |> String.split(~r/x|ext/, parts: 2) |> hd()
    digits = String.replace(text, ~r/\D/, "")
    international = text |> String.trim() |> String.starts_with?("+")

    cond do
      international and String.length(digits) in 8..15 ->
        "+" <> digits

      String.length(digits) == 10 ->
        "+1" <> digits

      String.length(digits) == 11 and String.starts_with?(digits, "1") ->
        "+" <> digits

      true ->
        nil
    end
  end

  @doc """
  A number to read, from D4H or as someone typed it: 604-555-1234 for North America, E.164
  for elsewhere, and text that isn't a number as written. Nil for none.
  """
  def format(phone) do
    case normalize(phone) do
      "+1" <> <<area::binary-3, exchange::binary-3, line::binary-4>> ->
        "#{area}-#{exchange}-#{line}"

      nil ->
        if phone && String.trim(phone) != "", do: String.trim(phone)

      e164 ->
        e164
    end
  end
end
