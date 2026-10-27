defmodule Web.Settings.LettersLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team
  alias App.Repo

  test "saves the signer's details, trimmed", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/letters")

    assert lv
           |> form("#letter-settings-form",
             form: %{authorized_by_title: " President ", authorized_by_phone: " 604-555-0100 "}
           )
           |> render_submit() =~ "Team settings saved."

    team = Team.get!(team.id)
    assert team.authorized_by_title == "President"
    assert team.authorized_by_phone == "604-555-0100"
  end

  test "the signer's email must look like one", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/letters")

    assert lv
           |> form("#letter-settings-form", form: %{authorized_by_email: "president"})
           |> render_submit() =~ "Enter an email like name@example.com."
  end

  describe "the signer's signature" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      %{conn: log_in_user(conn, user), team: team}
    end

    defp upload(lv, bytes, name \\ "signature.png") do
      lv
      |> file_input("#letter-settings-form", :signature, [
        %{name: name, content: bytes, type: "image/png"}
      ])
      |> render_upload(name)

      lv |> form("#letter-settings-form") |> render_submit()
    end

    test "uploads as a PNG, shows a preview, and removes", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/letters")
      refute has_element?(lv, "#signature-preview")

      upload(lv, png_fixture(1800, 400))

      assert has_element?(lv, "#signature-preview")
      signature = Repo.get!(Team, team.id).signature
      assert {:ok, image} = Image.from_binary(signature)
      # Scaled down to fit 900 pixels.
      assert Image.width(image) == 900

      lv |> element("#remove-signature") |> render_click()

      refute has_element?(lv, "#signature-preview")
      assert Repo.get!(Team, team.id).signature == nil
    end

    test "a file that is not an image is not saved", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/letters")

      upload(lv, "not an image")

      assert has_element?(lv, "#team-signature", "Use a PNG or JPEG image of the signature.")
      assert Repo.get!(Team, team.id).signature == nil
    end
  end
end
