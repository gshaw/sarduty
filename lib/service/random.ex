defmodule Service.Random do
  @moduledoc """
    Generates random data.
  """

  def uuid do
    Ecto.UUID.generate()
  end

  def hex(n \\ 16) do
    random_bytes = :crypto.strong_rand_bytes(n)
    Base.encode16(random_bytes, case: :lower)
  end

  @letters ~w(A B C E G H J K L M N P R S T V W X Y Z)
  @digits ~w(1 2 3 4 5 6 7 8 9)
  @letter_and_digits ~w(A B C E G H J K L M N P R S T V W X Y Z 1 2 3 4 5 6 7 8 9)

  @doc """
  Return a random string that starts with a letter, followed by one or more
  digits, followed by a single letter, followed by one or more digits.

  Token is designed to be unambiguous by removing similar looking characters
  and not have any chance of having a recognizable word that could be offensive.

  Example: Service.Random.token(10) # => "R41Z7S2W8P"
  """
  # Return a random
  def token(length) do
    generate_token(:letter, length, [])
  end

  defp generate_token(_next_type, n, characters) when n <= 0 do
    characters
    |> Enum.join()
    |> String.reverse()
  end

  defp generate_token(next_type, n, characters) do
    {character, next_type} = get_random(next_type)
    generate_token(next_type, n - 1, [character | characters])
  end

  defp get_random(:letter), do: {Enum.random(@letters), :digit}
  defp get_random(:digit), do: {Enum.random(@digits), :letter_or_digit}

  defp get_random(:letter_or_digit) do
    character = Enum.random(@letter_and_digits)
    {character, determine_next_type(character)}
  end

  defp determine_next_type(character) do
    if Enum.member?(@digits, character) do
      :letter_or_digit
    else
      :digit
    end
  end
end
