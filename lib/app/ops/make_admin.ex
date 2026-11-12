defmodule App.Ops.MakeAdmin do
  @moduledoc """
  Makes a login a SAR Duty admin, for the Admins page's "add an admin". The person logs in
  once first, so the login exists.
  """

  use App.Ops.Task,
    name: "make-admin",
    usage: "fix make-admin EMAIL",
    summary: "Makes a login a SAR Duty admin. They log in once first.",
    write: true

  alias App.Accounts
  alias App.Accounts.User
  alias App.Repo

  @impl App.Ops.Task
  def run([email]) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:error, "No login for #{email}. They log in once first."}

      %User{is_admin: true} ->
        {:ok, "#{email} was already an admin."}

      user ->
        user |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
        {:ok, "#{email} is an admin now."}
    end
  end

  def run(_args), do: {:error, "Usage: " <> usage()}
end
