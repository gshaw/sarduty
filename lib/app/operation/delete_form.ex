defmodule App.Operation.DeleteForm do
  @moduledoc """
  Deletes a form, an organization's or a team's, while no PDF was published from it: a
  form tried and never used. Once one was, turning it off is the way, so every published
  PDF keeps the form it printed from. Whoever may turn it on or off may delete it
  (App.Operation.SetFormState). Its page, any sign requests, and every draft of it go with it; answers stay,
  since they're the activity's and shared by name.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Form
  alias App.Model.PublishedPDF
  alias App.Operation.SaveDraft
  alias App.Operation.SetFormState
  alias App.Repo

  @doc "`:ok`, or `{:error, :forbidden | :published}`."
  def call(%Form{} = form, %User{} = user, now \\ DateTime.utc_now()) do
    cond do
      !SetFormState.allowed?(form, user, now) -> {:error, :forbidden}
      published?(form) -> {:error, :published}
      true -> delete(form, user)
    end
  end

  @doc "Whether the user may delete `form` now: the page shows Delete form only then."
  def allowed?(%Form{} = form, %User{} = user, now \\ DateTime.utc_now()),
    do: SetFormState.allowed?(form, user, now) and not published?(form)

  @doc "Whether any PDF, current or not, was published from `form`."
  def published?(%Form{id: id}),
    do: PublishedPDF |> where([p], p.form_id == ^id) |> Repo.exists?()

  defp delete(form, user) do
    # Each person's draft, with its PDFs in the file store; the rows would go with the
    # form, the files would not.
    SaveDraft.discard_all(form)

    Repo.transaction(fn ->
      Repo.delete!(form)

      Event.record!(:form_deleted,
        user_id: user.id,
        team_id: form.team_id,
        data: %{organization_id: form.organization_id, form_id: form.id, name: form.name}
      )
    end)

    :ok
  end
end
