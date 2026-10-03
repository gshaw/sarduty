defmodule App.Repo.Migrations.DecryptMemberContactDetails do
  use Ecto.Migration

  # Cloak is for credentials only (#113): every database copy is encrypted whole
  # with age (#111). The columns are already TEXT, so values are rewritten in
  # place. Migrations run at boot before the supervision tree, so start the Vault
  # here. members.coordinate is dropped: nothing has written it since 2023.
  @columns ~w(email phone address)

  def up do
    with_vault(fn -> rewrite(&decrypt/1) end)

    alter table(:members) do
      remove :coordinate
    end
  end

  def down do
    alter table(:members) do
      add :coordinate, :string
    end

    flush()
    with_vault(fn -> rewrite(&encrypt/1) end)
  end

  defp rewrite(fun) do
    %{rows: rows} = repo().query!("SELECT id, #{Enum.join(@columns, ", ")} FROM members")

    for [id | values] <- rows do
      sets = Enum.map_join(@columns, ", ", &"#{&1} = ?")
      repo().query!("UPDATE members SET #{sets} WHERE id = ?", Enum.map(values, fun) ++ [id])
    end
  end

  defp decrypt(nil), do: nil

  # Cloak returns :error, not a raise, for a value from another key. Raising rolls
  # the migration back and stops the boot, rather than writing :error over data.
  defp decrypt(value) do
    case value |> Base.decode64!() |> App.Vault.decrypt!() do
      plain when is_binary(plain) -> plain
      _ -> raise "A members value doesn't decrypt with CLOAK_KEY. Nothing was changed."
    end
  end

  defp encrypt(nil), do: nil
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
