defmodule App.Ops.CopyOrganizationLogos do
  @moduledoc """
  Copies each organization's logo from its `logo` column to the file store (#1067), reads
  it back byte for byte, then sets `logo_at`, which is what makes the app show it. An
  organization with a `logo_at` already is skipped, so a logo saved since the deploy is
  never overwritten and the task can run again. A one-off: delete it once it has run,
  in the PR that drops the column.
  """

  use App.Ops.Task,
    name: "copy-organization-logos",
    usage: "fix copy-organization-logos",
    summary: "Copies organization logos from SQLite to the file store (#1067).",
    write: true

  import Ecto.Query

  alias App.Adapter.FileStore
  alias App.Model.Organization
  alias App.Repo

  @impl App.Ops.Task
  def run([]) do
    if FileStore.available?() do
      now = DateTime.utc_now()

      rows =
        Organization
        |> where([o], not is_nil(o.logo))
        |> order_by([o], o.id)
        |> Repo.all()
        |> Enum.map(&[&1.id, &1.slug, byte_size(&1.logo), copy(&1, now)])

      {:ok, %{columns: ["id", "slug", "bytes", "outcome"], rows: rows}}
    else
      {:error, "This server has no file store."}
    end
  end

  def run(_args), do: {:error, "Usage: " <> usage()}

  @doc "Copies one organization's logo. Returns the outcome its row shows."
  def copy(%Organization{logo_at: %DateTime{}}, _now), do: "skipped, already in the store"

  def copy(%Organization{logo: logo} = organization, now) do
    key = Organization.logo_key(organization)

    with :ok <- FileStore.put(key, logo, "image/png"),
         {:ok, ^logo} <- FileStore.get(key) do
      Organization.put_logo_at!(organization, now)
      "copied"
    else
      {:ok, _other} -> "failed: read back different bytes"
      {:error, reason} -> "failed: #{inspect(reason)}"
    end
  end
end
