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

  test "a member team without a logo gets the organization's, not SAR Duty's" do
    team = team_fixture()
    plain = team_fixture()
    organization_fixture([team])

    logo = build_conn() |> get(~p"/teams/#{team.subdomain}/logo") |> response(200)
    sar_duty = build_conn() |> get(~p"/teams/#{plain.subdomain}/logo") |> response(200)

    assert logo != sar_duty
  end
end
