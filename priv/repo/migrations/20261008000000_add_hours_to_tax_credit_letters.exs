defmodule App.Repo.Migrations.AddHoursToTaxCreditLetters do
  use Ecto.Migration

  # Letters keep the hours they were created with (#192). Existing letters get theirs
  # from their own text; one that does not parse stays empty.
  def up do
    alter table(:tax_credit_letters) do
      add :primary_minutes, :integer
      add :secondary_minutes, :integer
    end

    flush()

    %{rows: rows} = repo().query!("SELECT id, letter_content FROM tax_credit_letters")

    for [id, content] <- rows,
        {primary, secondary} <- [parse_minutes(content)] do
      repo().query!(
        "UPDATE tax_credit_letters SET primary_minutes = ?, secondary_minutes = ? WHERE id = ?",
        [primary, secondary, id]
      )
    end
  end

  # TaxCreditLetter.parse_minutes/1 as it was before #970 removed it, so this migration
  # never changes.
  defp parse_minutes(content) when is_binary(content) do
    with {:ok, primary} <- parse_line(content, "Primary Hours"),
         {:ok, secondary} <- parse_line(content, "Secondary Hours") do
      {primary, secondary}
    else
      _ -> nil
    end
  end

  defp parse_minutes(_content), do: nil

  defp parse_line(content, label) do
    case Regex.run(~r/^#{label}: (.+)$/m, content) do
      [_line, value] -> parse_duration(String.trim(value))
      nil -> :error
    end
  end

  defp parse_duration(value) do
    # "1,204h 30m": drop thousands separators, not the comma in "212 hours, 30 minutes".
    value = String.replace(value, ~r/(?<=\d),(?=\d)/, "")

    case Regex.run(~r/^(\d+)h (\d+)m$|^(\d+) min$/, value) do
      [_all, hours, minutes] -> {:ok, to_minutes(hours, minutes)}
      [_all, "", "", minutes] -> {:ok, String.to_integer(minutes)}
      nil -> parse_long_duration(value)
    end
  end

  defp parse_long_duration(value) do
    case Regex.run(~r/^(?:(\d+) hours?)?(?:, )?(?:(\d+) minutes?)?$/, value) do
      [_all, hours] -> {:ok, String.to_integer(hours) * 60}
      [_all, hours, minutes] -> {:ok, to_minutes(hours, minutes)}
      _ -> :error
    end
  end

  defp to_minutes("", minutes), do: String.to_integer(minutes)
  defp to_minutes(hours, minutes), do: String.to_integer(hours) * 60 + String.to_integer(minutes)

  def down do
    alter table(:tax_credit_letters) do
      remove :primary_minutes
      remove :secondary_minutes
    end
  end
end
