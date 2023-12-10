# Custom Ecto type because cloak_ecto crashes when saving nil on Sqlite3? WTF?
# Also, using :binary type and skipping Base64 encoding fails as well.
# Maybe the issue is with the Ecto Sqlite adapter and nil binary columns?

defmodule App.Field.EncryptedString do
  use Ecto.Type

  # Database column must be type :string (not :binary)
  def type, do: :string

  def cast(value), do: {:ok, value}

  def dump(nil), do: {:ok, nil}

  def dump(value) do
    with {:ok, encrypted} <- App.Vault.encrypt(value) do
      {:ok, Base.encode64(encrypted)}
    end
  end

  def load(nil), do: {:ok, nil}

  def load(value) do
    with {:ok, decoded} <- Base.decode64(value) do
      App.Vault.decrypt(decoded)
    end
  end
end
