defmodule App.Field.EncryptedString do
  use Cloak.Ecto.Binary, vault: App.Vault
end
