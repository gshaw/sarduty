defmodule App.Operation.CopyForm do
  @moduledoc """
  Copies one of a team's organization's forms as the team's own, to change (#1083): its
  text and page, named "<name> (copy)", off. The copy is the team's from then on and
  shows beside the organization's on activities, never instead of it, so the
  organization's form stays the one its teams file. Saving checks the copy as any team
  form, on the team alone (App.Operation.SaveForm).
  """

  alias App.Accounts.User
  alias App.Model.Form
  alias App.Model.Team
  alias App.Operation.SaveForm

  @doc "Whether the user may copy the team's organization's forms: team forms on, and they save the team's forms."
  def allowed?(%Team{forms_enabled: true} = team, %User{} = user),
    do: SaveForm.allowed?(team, user)

  def allowed?(_team, _user), do: false

  @doc """
  `{:ok, copy}`; `{:error, message}` when the team already has a form by the copy's name,
  or it doesn't check on the team; or `{:error, :forbidden}`.
  """
  def call(%Form{} = form, %Team{} = team, %User{} = user) do
    cond do
      !allowed?(team, user) ->
        {:error, :forbidden}

      Form.get_organization_form(team, form.id) == nil ->
        {:error, :forbidden}

      true ->
        text = rename(form.text, "#{form.name} (copy)")

        case SaveForm.call(team, nil, text, Form.page_bytes(form), user) do
          {:ok, copy} -> {:ok, copy}
          {:error, :forbidden} -> {:error, :forbidden}
          {:error, _field, message} -> {:error, message}
        end
    end
  end

  # The text's first clause names the form, form 'Task report'; a quote inside is doubled.
  defp rename(text, name) do
    quoted = "'" <> String.replace(name, "'", "''") <> "'"

    Regex.replace(~r/^form\s+('(?:[^']|'')*'|"(?:[^"]|"")*")/m, text, "form " <> quoted,
      global: false
    )
  end
end
