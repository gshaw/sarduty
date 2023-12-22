defmodule App.Repo do
  use Ecto.Repo,
    otp_app: :sarduty,
    adapter: Ecto.Adapters.SQLite3

  use Scrivener, page_size: 50, max_page_size: 1000
end
