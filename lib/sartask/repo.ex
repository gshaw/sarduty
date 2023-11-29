defmodule Sartask.Repo do
  use Ecto.Repo,
    otp_app: :sartask,
    adapter: Ecto.Adapters.SQLite3
end
