defmodule App.Adapter.Outbox do
  @moduledoc """
  A Swoosh adapter that keeps every email in the Outbox (App.Model.OutboxMessage)
  instead of sending it: dev's, unless DEV_SEND_EMAIL is on. See docs/outbox.md.
  """
  use Swoosh.Adapter

  alias App.Model.OutboxMessage

  @impl Swoosh.Adapter
  def deliver(%Swoosh.Email{} = email, _config) do
    message = OutboxMessage.add_email!(email, email.private[:team_id])
    {:ok, %{id: message.id}}
  end
end
