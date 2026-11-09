defmodule App.Operation.SetFormState do
  @moduledoc """
  Sets an organization's form off, testing, or on for every team in it (#950, #970).
  Testing prints draft PDFs only; on publishes them. One of its organization admins
  does, or a SAR Duty admin; anyone else is refused, which also stops someone removed
  while the page is open. Turning a form off keeps every PDF published from it.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Form
  alias App.Model.OrganizationAdmin
  alias App.Repo

  @events %{off: :form_turned_off, testing: :form_set_testing, on: :form_turned_on}

  def call(%Form{} = form, state, %User{} = user) when is_map_key(@events, state) do
    if allowed?(form, user), do: set(form, state, user), else: {:error, :forbidden}
  end

  @doc "Whether the user may set the form's state."
  def allowed?(_form, %User{is_admin: true}), do: true

  def allowed?(%Form{organization_id: id}, %User{} = user),
    do: OrganizationAdmin.admin_of?(id, user)

  defp set(form, state, user) do
    Repo.transaction(fn ->
      form = form |> Ecto.Changeset.change(state: state, user_id: user.id) |> Repo.update!()

      Event.record!(@events[state],
        user_id: user.id,
        data: %{organization_id: form.organization_id, form_id: form.id}
      )

      form
    end)
  end
end
