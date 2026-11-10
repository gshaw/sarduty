defmodule Web.Settings.SignerLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team
  alias App.Operation.PrintTaxCreditLetter
  alias App.Repo
  alias Web.Settings.SignerLive

  test "saves the signer's details, trimmed", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/signer")

    assert lv
           |> form("#signer-form",
             form: %{authorized_by_title: " President ", authorized_by_phone: " 604-555-0100 "}
           )
           |> render_submit() =~ "Team settings saved."

    team = Team.get!(team.id)
    assert team.authorized_by_title == "President"
    assert team.authorized_by_phone == "604-555-0100"
  end

  # The address is on General now, and the old path is gone (#995).
  test "has no address, and Signer is the current tab", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/signer")

    refute has_element?(lv, "#form_mailing_address")

    assert has_element?(
             lv,
             ~s(a[aria-current="page"][href="/teams/#{team.subdomain}/settings/signer"]),
             "Signer"
           )
  end

  test "the signer's email must look like one", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/signer")

    assert lv
           |> form("#signer-form", form: %{authorized_by_email: "president"})
           |> render_submit() =~ "Enter an email like name@example.com."
  end

  describe "every letter ends like this (#995)" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      team =
        team
        |> Ecto.Changeset.change(
          authorized_by_name: "Alex Chen",
          authorized_by_title: "President",
          authorized_by_phone: "604-555-0112",
          authorized_by_email: nil
        )
        |> Repo.update!()

      %{conn: log_in_user(conn, user), team: team}
    end

    defp preview(lv), do: lv |> element("#signer-letter-end") |> render()

    test "signs by name, /s/ in front, with no upload", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/signer")

      assert has_element?(lv, "#signer-letter-end .letter-end-signature", "/s/ Alex Chen")
      assert has_element?(lv, "#signer-letter-end", "President")
      assert has_element?(lv, "#signer-letter-end", "604-555-0112")

      assert has_element?(
               lv,
               "#signer-preview-hint",
               "Certified on is the day a letter is emailed."
             )

      refute has_element?(lv, "#signer-unsaved")
      refute has_element?(lv, "input[type=file]")
      # One line for the name, not a box.
      assert has_element?(lv, ~s(input#form_authorized_by_name[type="text"]))
    end

    test "redraws as you type, says it isn't saved, and saves on Save settings",
         %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/signer")

      lv |> form("#signer-form", form: %{authorized_by_name: "Alexandra Chen"}) |> render_change()

      assert has_element?(lv, "#signer-letter-end .letter-end-signature", "/s/ Alexandra Chen")
      assert has_element?(lv, "#signer-preview h2", "Once you save, every letter ends like this")
      assert has_element?(lv, "#signer-unsaved", "Not saved")
      assert has_element?(lv, "#signer-preview-hint", "Save settings to use it on new letters.")
      assert Team.get!(team.id).authorized_by_name == "Alex Chen"

      # Typing back to what's saved clears both.
      lv |> form("#signer-form", form: %{authorized_by_name: "Alex Chen"}) |> render_change()
      refute has_element?(lv, "#signer-unsaved")

      lv |> form("#signer-form", form: %{authorized_by_name: "Alexandra Chen"}) |> render_submit()
      assert Team.get!(team.id).authorized_by_name == "Alexandra Chen"
      refute has_element?(lv, "#signer-unsaved")
      assert has_element?(lv, "#signer-preview h2", "Every letter ends like this")
    end

    test "a blank the letter needs shows in its place; a blank phone drops out",
         %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/signer")

      lv
      |> form("#signer-form", form: %{authorized_by_title: "", authorized_by_phone: ""})
      |> render_change()

      assert has_element?(lv, "#signer-letter-end .letter-end-needed", "Signer's title: needed")
      refute preview(lv) =~ "604-555"
    end

    # The preview's script is the font letters print in, the same file.
    test "the web font is the letters' font" do
      assert File.read!("priv/static/fonts/dancing-script.ttf") ==
               File.read!("priv/fonts/DancingScript[wght].ttf")
    end

    # The preview is the letter's own end, line for line, as it prints today.
    test "its lines are the end of the letter's text", %{team: team} do
      member = member_fixture(team)
      now = DateTime.utc_now()
      read = PrintTaxCreditLetter.read(team, member.id, now.year, now)
      text = PrintTaxCreditLetter.text(team, read)
      today = Service.Period.today(now, team.timezone)

      lines =
        for {_kind, line} <- SignerLive.ending(team, today, PrintTaxCreditLetter.need_names()),
            do: line

      assert String.ends_with?(text, Enum.join(lines, "\n"))
      assert hd(lines) =~ "Certified on"
    end
  end
end
