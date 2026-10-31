defmodule Web.HelpLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture(%{name: "Cameron Ruiz"})
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  defp with_contacts(team) do
    alex = member_fixture(team, %{name: "Alex Chen", email: "alex.chen@example.com"})
    sam = member_fixture(team, %{name: "Sam Rivera", email: "sam.rivera@example.com"})

    team =
      team
      |> Ecto.Changeset.change(first_contact_id: alex.id, second_contact_id: sam.id)
      |> App.Repo.update!()

    {team, alex, sam}
  end

  test "the team is ticked to start, with its contacts named, and the people to ask beside it",
       %{conn: conn, team: team} do
    {team, alex, _sam} = with_contacts(team)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/help")

    assert has_element?(lv, "#help-to-team[checked]")
    refute has_element?(lv, "#help-to-site-admins[checked]")
    assert has_element?(lv, "#help-to", "Alex Chen and Sam Rivera")
    assert has_element?(lv, "#help-to", "Gerry Shaw and Andrew Wallwork")
    assert has_element?(lv, "#help-contact-#{alex.id}", "Alex Chen")
    assert has_element?(lv, ~s{#help-contact-#{alex.id} a[href="mailto:alex.chen@example.com"]})

    assert has_element?(
             lv,
             ~s{#help-site-admin-0 a[href="mailto:support@sarduty.com"]},
             "support@sarduty.com"
           )
  end

  test "sends one email to everyone ticked, Reply-To the member, and says who got it",
       %{conn: conn, team: team, user: user} do
    {team, _alex, _sam} = with_contacts(team)
    from = "/teams/#{team.subdomain}/me"
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/help?#{[from: from]}")

    lv
    |> form("#help-form", help: %{to: ["", "team", "site_admins"], message: "My hours show 0."})
    |> render_submit()

    assert has_element?(
             lv,
             "#help-sent",
             "Sent to Alex Chen, Sam Rivera, and the SAR Duty site admins"
           )

    assert has_element?(lv, "#help-sent", user.email)

    assert_email_sent(fn email ->
      assert email.to == [
               {"Alex Chen", "alex.chen@example.com"},
               {"Sam Rivera", "sam.rivera@example.com"},
               {"SAR Duty site admins", "support@sarduty.com"}
             ]

      assert email.reply_to == {"Cameron Ruiz", user.email}
      assert email.cc == [{"Cameron Ruiz", user.email}]
      assert email.text_body =~ "They came from #{Web.Endpoint.url()}#{from}."
    end)
  end

  test "nothing ticked or no message says what to fix, and sends nothing", %{
    conn: conn,
    team: team
  } do
    {team, _alex, _sam} = with_contacts(team)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/help")

    lv |> form("#help-form", help: %{to: [""], message: ""}) |> render_submit()

    assert has_element?(lv, "#help-to", "Select who to send it to")
    assert has_element?(lv, "#help-form", "Enter a message")
    refute_email_sent()
  end

  test "a team with no contacts is greyed out, and the site admins are ticked instead",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/help")

    assert has_element?(lv, "#help-to-team[disabled]")
    refute has_element?(lv, "#help-to-team[checked]")
    assert has_element?(lv, "#help-to-site-admins[checked]")
    assert has_element?(lv, "#help-to", "No team contacts yet")
    assert has_element?(lv, "#help-team-contacts", "None yet")

    # A forged "team" sends to the site admins only: never every team admin.
    lv
    |> form("#help-form", help: %{message: "Who do I ask?"})
    |> render_submit(%{help: %{to: ["team", "site_admins"]}})

    assert_email_sent(fn email ->
      email.to == [{"SAR Duty site admins", "support@sarduty.com"}]
    end)
  end

  test "Get help is last in the side navigation, saying the page it was opened on",
       %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")

    href =
      "/teams/#{team.subdomain}/help?" <> URI.encode_query(from: "/teams/#{team.subdomain}/me")

    assert has_element?(
             lv,
             ~s{#side-nav .side-nav-group:last-child #side-nav-help[href="#{href}"]},
             "Get help"
           )

    assert has_element?(lv, ~s{#phone-menu #phone-nav-help[href="#{href}"]})
    refute has_element?(lv, "#switch-help")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/help")

    assert has_element?(
             lv,
             ~s{#side-nav-help[href="/teams/#{team.subdomain}/help"][aria-current=page]}
           )
  end

  test "a from that leaves the site is dropped", %{conn: conn, team: team} do
    {team, _alex, _sam} = with_contacts(team)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/help?#{[from: "//evil.example.com"]}")

    lv |> form("#help-form", help: %{to: ["", "team"], message: "Hi"}) |> render_submit()

    assert_email_sent(&(not String.contains?(&1.text_body, "They came from")))
  end
end
