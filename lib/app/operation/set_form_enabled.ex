defmodule App.Operation.SetFormEnabled do
  @moduledoc """
  Turns an organization's form on or off for every team in it (#950). One of its
  organization admins does, or a SAR Duty admin; anyone else is refused, which also stops
  someone removed while the page is open.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Form
  alias App.Model.OrganizationAdmin
  alias App.Repo

  def call(%Form{} = form, enabled, %User{} = user) when is_boolean(enabled) do
    if allowed?(form, user), do: set(form, enabled, user), else: {:error, :forbidden}
  end

  @doc "Whether the user may turn the form on or off."
  def allowed?(_form, %User{is_admin: true}), do: true

  def allowed?(%Form{organization_id: id}, %User{} = user),
    do: OrganizationAdmin.admin_of?(id, user)

  defp set(form, enabled, user) do
    Repo.transaction(fn ->
      form = form |> Ecto.Changeset.change(enabled: enabled, user_id: user.id) |> Repo.update!()

      Event.record!(if(enabled, do: :form_turned_on, else: :form_turned_off),
        user_id: user.id,
        data: %{organization_id: form.organization_id, form_id: form.id}
      )

      form
    end)
  end
end
