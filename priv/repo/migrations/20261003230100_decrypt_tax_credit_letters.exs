defmodule App.Repo.Migrations.DecryptTaxCreditLetters do
  use Ecto.Migration

  # Letter text becomes plain, like member contact details in the previous
  # migration (#113). The column is already TEXT.
  def up, do: with_vault(fn -> rewrite(&decrypt/1) end)
  def down, do: with_vault(fn -> rewrite(&encrypt/1) end)

  defp rewrite(fun) do
    %{rows: rows} = repo().query!("SELECT id, letter_content FROM tax_credit_letters")

    for [id, content] <- rows do
      repo().query!("UPDATE tax_credit_letters SET letter_content = ? WHERE id = ?", [
        fun.(content),
        id
      ])
    end
  end

  # See the members migration: a value from another key must stop the boot.
  defp decrypt(value) do
    case value |> Base.decode64!() |> App.Vault.decrypt!() do
      plain when is_binary(plain) -> plain
      _ -> raise "A letter doesn't decrypt with CLOAK_KEY. Nothing was changed."
    end
  end

  defp encrypt(value), do: value |> App.Vault.encrypt!() |> Base.encode64()

  # Stop a Vault started here, or the app's own fails to start after migrating.
  defp with_vault(fun) do
    case App.Vault.start_link() do
      {:ok, pid} ->
        fun.()
        GenServer.stop(pid)

      {:error, {:already_started, _}} ->
        fun.()
    end
  end
end
