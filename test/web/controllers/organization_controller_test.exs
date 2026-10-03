defmodule Web.OrganizationControllerTest do
  use Web.ConnCase

  import App.DataFixtures

  test "sends the logo padded square, without a login" do
    organization = organization_fixture()

    conn = get(build_conn(), ~p"/organizations/#{organization.slug}/logo")

    image = conn |> response(200) |> Image.from_binary!()
    assert {Image.width(image), Image.height(image)} == {660, 660}
  end

  test "404s for an organization with no logo, or none at all" do
    organization = organization_fixture([], %{logo: nil})

    assert build_conn() |> get(~p"/organizations/#{organization.slug}/logo") |> response(404)
    assert build_conn() |> get(~p"/organizations/nobody/logo") |> response(404)
  end
end
