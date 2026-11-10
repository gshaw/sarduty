defmodule App.Operation.AddDemoForms do
  @moduledoc """
  Gives an organization WESARA's made-up forms (#963), from priv/forms/wesara, turned on:
  each demo's copy of WESARA and the dev teams' WESARA (App.Operation.BuildDemoTeam), so
  a visitor or a branch on a dev server tries forms and Publish. A demo team's PDFs say
  SAMPLE, as all its PDFs do.

  It skips App.Operation.SaveForm's checks, which run every form on every team and would
  slow each demo's build. App.FormsTest saves and prints every form in priv/forms, these
  included, so a form that wouldn't pass never gets here. WESARA's forms read only an
  activity's own fields, never a custom field, so they print on any team.
  """

  alias App.Document
  alias App.Model.Form
  alias App.Model.FormPage
  alias App.Model.Organization
  alias App.Repo

  @doc "The forms' files: each `.txt`, and its `.pdf` page when it has one."
  def paths do
    dir = Application.app_dir(:sarduty, "priv/forms/wesara")

    for name <- dir |> File.ls!() |> Enum.sort(),
        Path.extname(name) == ".txt",
        do: Path.join(dir, Path.rootname(name))
  end

  @doc "Adds each form to `organization`, on. Returns the forms."
  def call(%Organization{} = organization) do
    {:ok, forms} = Repo.transaction(fn -> Enum.map(paths(), &insert!(organization, &1)) end)
    forms
  end

  defp insert!(organization, path) do
    text = File.read!(path <> ".txt")
    page = if File.exists?(path <> ".pdf"), do: File.read!(path <> ".pdf")
    {:ok, doc} = Document.parse(text)

    form =
      Repo.insert!(%Form{
        organization_id: organization.id,
        name: doc.name,
        about: doc.about,
        text: text,
        page_sha256: Form.sha256(page),
        state: :on
      })

    if page, do: Repo.insert!(%FormPage{form_id: form.id, bytes: page})
    form
  end
end
