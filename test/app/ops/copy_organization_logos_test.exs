defmodule App.Ops.CopyOrganizationLogosTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.FileStore
  alias App.Model.Organization
  alias App.Ops.CopyOrganizationLogos

  # Before #1067 a logo was only in the column, with no logo_at.
  defp old_organization(logo) do
    organization_fixture([], %{logo: nil})
    |> Ecto.Changeset.change(logo: logo)
    |> Repo.update!()
  end

  test "copies each logo to the file store, then sets logo_at" do
    png = png_fixture(200, 200)
    old = old_organization(png)
    none = organization_fixture([], %{logo: nil})

    assert {:ok, %{rows: rows}} = CopyOrganizationLogos.run([])
    assert [old.id, old.slug, byte_size(png), "copied"] in rows
    refute Enum.any?(rows, &(hd(&1) == none.id))

    assert old |> Organization.logo_key() |> FileStore.get() == {:ok, png}
    assert Repo.reload!(old).logo_at
  end

  test "skips one whose logo is in the store already, so a newer logo stays" do
    organization = organization_fixture()
    key = Organization.logo_key(organization)
    {:ok, newer} = FileStore.get(key)
    organization = organization |> Ecto.Changeset.change(logo: "old png") |> Repo.update!()

    assert CopyOrganizationLogos.copy(organization, DateTime.utc_now()) ==
             "skipped, already in the store"

    assert FileStore.get(key) == {:ok, newer}
  end
end
