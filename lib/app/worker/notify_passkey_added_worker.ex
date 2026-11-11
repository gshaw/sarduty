defmodule App.Worker.NotifyPasskeyAddedWorker do
  @moduledoc """
  Emails a user that a passkey was added to their account (#129). Sends nothing once the
  passkey is gone: removed, it can no longer log anyone in.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Accounts.UserNotifier
  alias App.Accounts.UserPasskey
  alias App.Repo

  @doc "Queues the email for a passkey just added."
  def enqueue(%UserPasskey{id: id}), do: %{passkey_id: id} |> new() |> Oban.insert!()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"passkey_id" => id}}) do
    case UserPasskey |> Repo.get(id) |> Repo.preload(:user) do
      %UserPasskey{} = passkey ->
        with {:ok, _email} <- UserNotifier.deliver_passkey_added(passkey.user, passkey), do: :ok

      nil ->
        :ok
    end
  end
end
