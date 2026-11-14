defmodule App.Operation.SaveForm do
  @moduledoc """
  Uploads an organization's or a team's form, or replaces one (#950, #1083): its text and
  its page PDF. Only a SAR Duty admin does, since SAR Duty prepares each form's places;
  there's no editor in the browser.

  Saving checks an organization's form against the catalog of each of its teams and of
  Coast Range SAR, where its organization admins try it, so it prints on every one of
  them. No team's RESTRICTED field passes that check, since the form is the
  organization's (docs/organizations.md). A team's form is checked on that team alone,
  RESTRICTED fields and all, and can't take the name of one of its organization's forms.
  Every `expect` must hold, and every place must be on a page of its page PDF. A form
  with a layout has no page, and its layout must print.

  Replacing it raises its version.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Document
  alias App.Model.Event
  alias App.Model.Form
  alias App.Model.FormPage
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.PrintDocument
  alias App.Repo
  alias App.Report.Context
  alias App.Report.Error
  alias App.SampleRepo

  @doc """
  `{:ok, form}`; `{:error, field, message}`, where `field` is `:text` or `:page`, the
  file to fix; or `{:error, :forbidden}` for anyone but a SAR Duty admin. `form` is nil
  for a new one. `page` is the page PDF's bytes; nil when replacing keeps the form's, if
  the new text says page.
  """
  def call(owner, form, text, page, %User{} = user, now \\ DateTime.utc_now()) do
    cond do
      !user.is_admin -> {:error, :forbidden}
      form && !owned?(form, owner) -> {:error, :forbidden}
      true -> save(owner, form, text, page || kept_page(form, text), user, now)
    end
  end

  defp owned?(%Form{organization_id: id}, %Organization{id: id}), do: true
  defp owned?(%Form{team_id: id}, %Team{id: id}), do: true
  defp owned?(_form, _owner), do: false

  # Replacing keeps the form's page while its text prints on one, and drops it for a
  # layout.
  defp kept_page(nil, _text), do: nil

  defp kept_page(%Form{} = form, text) do
    case Document.parse(text) do
      {:ok, %Document{page: true}} -> Form.page_bytes(form)
      _other -> nil
    end
  end

  defp save(owner, form, text, page, user, now) do
    with {:ok, doc} <- check(text, page, contexts(owner, now)),
         :ok <- check_name(owner, doc) do
      result = Repo.transaction(fn -> write!(owner, form, doc, text, page, user) end)

      case result do
        {:ok, saved} -> {:ok, saved}
        {:error, message} -> {:error, :text, message}
      end
    end
  end

  # A team's form can't take its organization's form's name: the organization's would
  # replace it on every activity (App.Model.Form.shown_for/1).
  defp check_name(%Team{organization_id: id}, doc) when is_integer(id) do
    taken? =
      Form |> where([f], f.organization_id == ^id and f.name == ^doc.name) |> Repo.exists?()

    if taken?,
      do:
        {:error, :text,
         "#{Repo.get!(Organization, id).short_name} has a form called #{doc.name}. Give yours another name."},
      else: :ok
  end

  defp check_name(_owner, _doc), do: :ok

  # The form, its page, and an event, or a rollback with what to fix.
  defp write!(owner, form, doc, text, page, user) do
    changeset = changeset(owner, form, doc, text, page, user)

    case Repo.insert_or_update(changeset) do
      {:ok, saved} ->
        put_page!(saved, page)

        Event.record!(:form_saved,
          user_id: user.id,
          team_id: saved.team_id,
          data: Map.merge(owner_data(owner), %{form_id: saved.id, version: saved.version})
        )

        saved

      {:error, _changeset} ->
        Repo.rollback(
          "#{owner_name(owner)} has a form called #{doc.name}. Replace that one instead."
        )
    end
  end

  defp owner_data(%Organization{id: id}), do: %{organization_id: id}
  defp owner_data(%Team{id: id}), do: %{team_id: id}

  defp owner_name(%Organization{short_name: name}), do: name
  defp owner_name(%Team{name: name}), do: name

  defp new_form(%Organization{id: id}), do: %Form{organization_id: id}
  defp new_form(%Team{id: id}), do: %Form{team_id: id}

  defp unique_index(%Organization{}), do: :forms_organization_id_name_index
  defp unique_index(%Team{}), do: :forms_team_id_name_index

  defp changeset(owner, form, doc, text, page, user) do
    changes = %{
      name: doc.name,
      about: doc.about,
      text: text,
      page_sha256: Form.sha256(page),
      user_id: user.id
    }

    {form, changes} =
      case form do
        nil -> {new_form(owner), changes}
        %Form{} -> {form, Map.put(changes, :version, form.version + 1)}
      end

    form
    |> Ecto.Changeset.change(changes)
    |> Ecto.Changeset.unique_constraint(:name, name: unique_index(owner))
  end

  defp put_page!(form, page) do
    FormPage |> where([p], p.form_id == ^form.id) |> Repo.delete_all()
    if page, do: Repo.insert!(%FormPage{form_id: form.id, bytes: page})
  end

  @doc """
  `{:ok, doc}`, the form checked, or `{:error, field, message}`: the text against each catalog
  in `contexts`, `[{name, %Context{}}]`, then its `expect` lines, then its page, then
  that its layout prints. Reads each context's database only through the catalog the
  context already holds.
  """
  def check(text, page, contexts) when is_binary(text) do
    with {:ok, doc} <- parse(text),
         {:ok, doc} <- check_contexts(doc, contexts),
         :ok <- expects(doc),
         :ok <- check_page(doc, page),
         :ok <- check_layout(doc),
         do: {:ok, doc}
  end

  defp check_layout(doc) do
    case PrintDocument.check_layout(doc) do
      :ok -> :ok
      {:error, reason} -> {:error, :text, reason}
    end
  end

  defp parse(text) do
    case Document.parse(text) do
      {:ok, %Document{kind: :form} = doc} -> {:ok, doc}
      {:ok, _doc} -> {:error, :text, "Start the text with form and the form's name."}
      {:error, %Error{} = error} -> {:error, :text, Error.text(error)}
    end
  end

  # Checked on every team, and the last check's types kept: they're the same everywhere
  # the check passed.
  defp check_contexts(doc, contexts) do
    Enum.reduce_while(contexts, {:ok, doc}, fn {name, context}, _checked ->
      case Document.check(doc, context) do
        {:ok, checked} -> {:cont, {:ok, checked}}
        {:error, %Error{} = error} -> {:halt, {:error, :text, "#{name}: #{Error.text(error)}"}}
      end
    end)
  end

  # The catalog without a team's RESTRICTED fields: they're the team's alone, so an
  # organization's form never reads one.
  defp without_restricted(%Context{custom_fields: custom} = context) do
    custom =
      Map.new(custom, fn
        {subject, defs} when is_list(defs) -> {subject, Enum.reject(defs, & &1.restricted?)}
        other -> other
      end)

    %{context | custom_fields: custom}
  end

  defp expects(doc) do
    case Document.expect(doc) do
      :ok -> :ok
      {:error, errors} -> {:error, :text, Enum.map_join(errors, " ", &Error.text/1)}
    end
  end

  defp check_page(%Document{page: true}, nil),
    do: {:error, :page, "Upload the form's page. Its text says page."}

  defp check_page(%Document{page: true} = doc, page) do
    case PrintDocument.check_page(doc.places, page) do
      {:ok, _pages} -> :ok
      {:error, reason} -> {:error, :page, reason}
    end
  end

  defp check_page(_doc, nil), do: :ok

  defp check_page(%Document{layout: %{}}, _page),
    do: {:error, :page, "Upload no page: the form's layout draws it."}

  defp check_page(_doc, _page),
    do: {:error, :page, "Add page to the form's text, or upload no page."}

  @doc """
  The catalogs a form is checked against, `[{name, %Context{}}]`: for an organization's,
  each of its teams, A to Z, without their RESTRICTED fields, then Coast Range SAR,
  where it's tried, when seeded; for a team's, that team.
  """
  def contexts(%Organization{id: id}, now) do
    teams =
      Team
      |> where([t], t.organization_id == ^id)
      |> order_by([t], asc: t.name)
      |> Repo.all()
      |> Enum.map(&{&1.name, Context.new(&1, now)})

    sample =
      case SampleRepo.team() do
        nil -> []
        team -> [{team.name, Context.new(team, now, repo: SampleRepo)}]
      end

    teams
    |> Enum.concat(sample)
    |> Enum.map(fn {name, context} -> {name, without_restricted(context)} end)
  end

  def contexts(%Team{} = team, now), do: [{team.name, Context.new(team, now)}]
end
