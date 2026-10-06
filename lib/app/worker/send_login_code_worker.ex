defmodule App.Worker.SendLoginCodeWorker do
  @moduledoc """
  Sends a login code by email or text, or nothing when the email or number may not log
  in. The login form queues one for every request and never sends inline, so the reply
  takes the same time whether or not someone has access (#176).
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email}}), do: Accounts.deliver_login_code(email)
  def perform(%Oban.Job{args: %{"phone" => phone}}), do: Accounts.deliver_login_text(phone)
end
