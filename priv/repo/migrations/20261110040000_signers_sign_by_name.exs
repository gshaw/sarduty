defmodule App.Repo.Migrations.SignersSignByName do
  use Ecto.Migration

  # A letter's signer signs by typing their name (#995): "/s/ Alex Chen" in a script, so
  # the team's signature picture goes. The Signer tab's box is one line now, so a signer
  # that holds more than a name is cleaned up first:
  #
  # - the name is the first line, up to its first comma;
  # - the title, only when it's blank, is the text after that comma, or else line 2;
  # - a line that is an email or a phone number moves to that field, when it's blank;
  # - everything else, such as an address, is dropped.
  #
  # Down gives back the column, empty: the pictures, and the dropped lines, are gone.
  def up do
    %{rows: rows} =
      repo().query!("""
      SELECT id, authorized_by_name, authorized_by_title, authorized_by_phone,
        authorized_by_email
      FROM teams
      WHERE authorized_by_name IS NOT NULL
      """)

    for [id | old] <- rows, (new = split(old)) != old do
      repo().query!(
        """
        UPDATE teams
        SET authorized_by_name = ?1, authorized_by_title = ?2, authorized_by_phone = ?3,
          authorized_by_email = ?4
        WHERE id = ?5
        """,
        new ++ [id]
      )
    end

    alter table(:teams) do
      remove :signature
    end
  end

  def down do
    alter table(:teams) do
      add :signature, :binary
    end
  end

  @doc "`[name, title, phone, email]` with the name one line, as the rules above say."
  def split([name, title, phone, email] = signer) do
    case name
         |> String.split(~r/\r?\n/)
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == "")) do
      [] -> signer
      [first | rest] -> split(first, rest, [title, phone, email])
    end
  end

  defp split(first, rest, [title, phone, email]) do
    {name, after_comma} =
      case String.split(first, ",", parts: 2) do
        [name, after_comma] -> {String.trim(name), blank(after_comma)}
        [name] -> {name, nil}
      end

    second = List.first(rest)

    [
      name,
      present(title) || after_comma || if(second && not contact?(second), do: second),
      present(phone) || Enum.find_value(rest, &phone/1),
      present(email) || Enum.find_value(rest, &email/1)
    ]
  end

  defp contact?(line), do: email(line) != nil or phone(line) != nil

  # An email or a phone number alone on its line, maybe after a word such as "Tel:".
  defp email(line) do
    case Regex.run(~r/^(?:e-?mail[.:]?\s*)?([^\s@]+@[^\s@]+\.[^\s@]+)$/i, line) do
      [_line, email] -> email
      nil -> nil
    end
  end

  defp phone(line) do
    with [_line, phone] <-
           Regex.run(~r/^(?:(?:tel|phone|cell|mobile)[.:]?\s*)?(\+?[\d\s().-]+)$/i, line),
         true <- phone |> String.replace(~r/\D/, "") |> String.length() >= 7 do
      String.trim(phone)
    else
      _no -> nil
    end
  end

  defp blank(text), do: text |> String.trim() |> present()

  defp present(nil), do: nil
  defp present(text), do: if(String.trim(text) == "", do: nil, else: text)
end
