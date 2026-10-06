defmodule App.Worker.NotifyLoginBlockedWorker do
  @moduledoc """
  Emails the owner of an email or number that wrong login codes have blocked (#176).
  Queued rather than sent inline, so the reply to a wrong code takes the same time
  whether or not the account exists. Sends nothing for an email or number with no
  account.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Accounts
  alias App.Accounts.User
  alias App.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email}}), do: notify(email)

  def perform(%Oban.Job{args: %{"phone" => phone}}) do
    if Accounts.text_login?(), do: phone |> Accounts.text_login_email() |> notify(), else: :ok
  end

  defp notify(nil), do: :ok

  defp notify(email) do
    case Accounts.get_user_by_email(email) do
      %User{email: address} ->
        with {:ok, _} <- UserNotifier.deliver_login_blocked(address), do: :ok

      nil ->
        :ok
    end
  end
end
