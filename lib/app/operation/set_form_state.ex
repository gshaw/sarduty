defmodule App.Operation.SetFormState do
  @moduledoc """
  Sets a form off, testing, or on (#950, #970): an organization's for every team in it,
  a team's for that team (#1083). Testing prints draft PDFs only; on publishes them. One
  of its organization admins does, or the team's admins for a team's form, or a SAR Duty
  admin; anyone else is refused, which also stops someone removed while the page is
  open. Turning a form off keeps every PDF published from it.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Form
  alias App.Model.OrganizationAdmin
  alias App.Model.Team
  alias App.Repo

  @events %{off: :form_turned_off, testing: :form_set_testing, on: :form_turned_on}

  def call(%Form{} = form, state, %User{} = user, now \\ DateTime.utc_now())
      when is_map_key(@events, state) do
    if allowed?(form, user, now), do: set(form, state, user), else: {:error, :forbidden}
  end

  @doc "Whether the user may set the form's state."
  def allowed?(form, user, now \\ DateTime.utc_now())

  def allowed?(_form, %User{is_admin: true}, _now), do: true

  def allowed?(%Form{team_id: nil, organization_id: id}, %User{} = user, _now),
    do: OrganizationAdmin.admin_of?(id, user)

  def allowed?(%Form{team_id: id}, %User{email: email}, now),
    do: id |> Team.get() |> Team.managed_by?(email, now)

  defp set(form, state, user) do
    Repo.transaction(fn ->
      form = form |> Ecto.Changeset.change(state: state, user_id: user.id) |> Repo.update!()

      Event.record!(@events[state],
        user_id: user.id,
        team_id: form.team_id,
        data: %{organization_id: form.organization_id, form_id: form.id}
      )

      form
    end)
  end
end
