defmodule Web.FormPagesTest do
  use Web.ConnCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias App.Model.Event
  alias App.Model.Form
  alias App.Operation.SaveForm
  alias App.Operation.SetAISettings
  alias App.Repo
  alias Web.Components.TeamSettingsTabs

  @text File.read!("test/support/fixtures/forms/task_report.txt")
  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup_all do
    {:ok, page} = Service.Typst.compile(@page_source)
    %{page: page}
  end

  # Dana is an organization admin of WSARA. Its one team has the fields the test form
  # reads, as a BC team has BCSARA's.
  setup %{page: page} do
    team = team_fixture(%{name: "Valley SAR"})

    custom_field_fixture(team, %{
      title: "What was SAR tasked to do?",
      field_type: "single_choice",
      options: [%{"id" => 1, "label" => "Search - lost subject(s)"}]
    })

    custom_field_fixture(team, %{title: "People helped", field_type: "number"})

    organization =
      organization_fixture([team], %{
        name: "Western SAR Association",
        short_name: "WSARA",
        slug: "wsara"
      })

    dana = user_fixture()
    organization_admin_fixture(organization, dana.email)

    %{
      team: team,
      organization: organization,
      dana: dana,
      form: form_fixture(organization, %{page: page})
    }
  end

  defp sar_duty_admin do
    admin = user_fixture(%{is_admin: true})
    # A SAR Duty admin logs in only while D4H lists them somewhere (#141).
    member_fixture(team_fixture(), %{email: admin.email, d4h_permission: 2})
    admin
  end

  describe "Forms" do
    test "lists each form, on or off", %{conn: conn, dana: dana, form: form} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/forms")

      assert has_element?(lv, "#form-#{form.id}-name", "Task report")
      assert has_element?(lv, "#form-#{form.id}-state", "Off")
      assert has_element?(lv, "#side-nav a[href='/orgs/wsara/forms']")
      assert has_element?(lv, "#new-form[href='/orgs/wsara/forms/new']", "New form")
    end

    test "says to start one from the agency's PDF when there are none",
         %{conn: conn, dana: dana, form: form} do
      Repo.delete!(form)
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/forms")
      assert has_element?(lv, "#no-forms", "Choose New form and give SAR Duty the agency's PDF.")
    end
  end

  describe "a form" do
    test "shows what it reads and asks, and its text",
         %{conn: conn, dana: dana, form: form} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/forms/#{form}")

      assert has_element?(lv, "#form-shows-on", "Activities where kind = 'incident'")
      assert has_element?(lv, "#form-questions", "Task leader")
      assert has_element?(lv, "#form-page", "2 pages")
      assert has_element?(lv, "#form-text", "for activity where kind = 'incident'")
      refute has_element?(lv, "#form-replace")
    end

    test "its organization admin sets it testing, on, and off (#970)",
         %{conn: conn, dana: dana, form: form} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/forms/#{form}")

      # Off: Testing waits under Turned on.
      assert has_element?(lv, "#form-testing[disabled]")

      # Turning it on starts testing.
      lv |> element("#form-on") |> render_click()
      assert Repo.reload!(form).state == :testing
      assert has_element?(lv, "#form-state", "Testing")
      assert has_element?(lv, "#form-on[checked]")
      assert has_element?(lv, "#form-testing[checked]:not([disabled])")

      lv |> element("#form-testing") |> render_click()
      assert Repo.reload!(form).state == :on
      assert has_element?(lv, "#form-state", "On")
      refute has_element?(lv, "#form-testing[checked]")

      lv |> element("#form-on") |> render_click()
      assert Repo.reload!(form).state == :off
      refute has_element?(lv, "#form-on[checked]")

      kinds = [:form_set_testing, :form_turned_on, :form_turned_off]
      assert [_testing, _on, _off] = Event |> where([e], e.kind in ^kinds) |> Repo.all()
    end

    test "tries it on Coast Range SAR's activities", %{conn: conn, dana: dana, form: form} do
      conn = log_in_user(conn, dana)
      {:ok, lv, _html} = live(conn, ~p"/orgs/wsara/forms/#{form}")

      assert has_element?(lv, "#form-try-activity option", "Missing hiker")
      [activity_id] = lv |> element("#form-try-activity option[selected]") |> render() |> ids()

      conn = get(conn, ~p"/orgs/wsara/forms/#{form}/try?#{[activity: activity_id]}")
      assert "%PDF" <> _ = response(conn, 200)
      assert response_content_type(conn, :pdf) =~ "application/pdf"
    end

    test "one with a layout has no page: its layout draws it", ctx do
      %{conn: conn, dana: dana, organization: organization} = ctx

      form =
        form_fixture(organization, %{
          name: "Expense reimbursement request",
          text: File.read!("priv/forms/bcsara/expense_request.txt"),
          page: nil
        })

      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/forms/#{form}")
      assert has_element?(lv, "#form-page", "Drawn by its layout")
      assert has_element?(lv, "#form-text", "EMCR HEADQUARTERS USE ONLY")
    end

    test "opens its blank page", %{conn: conn, dana: dana, form: form, page: page} do
      conn = conn |> log_in_user(dana) |> get(~p"/orgs/wsara/forms/#{form}/page")
      assert response(conn, 200) == page
    end

    test "another organization's form is a 404, as are its PDFs", %{conn: conn, dana: dana} do
      other = form_fixture(organization_fixture())
      conn = log_in_user(conn, dana)

      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/#{other}") end
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/#{other}/page") end
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/#{other}/try") end
    end

    test "someone else gets a 404 on its PDFs", %{conn: conn, form: form} do
      conn = log_in_user(conn, user_fixture())
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/#{form}/page") end
    end
  end

  # The same New form and Change form a team has (#1089), for its organization admins.
  describe "an organization's New form and Change form" do
    test "its organization admin starts one from the agency's PDF", ctx do
      %{conn: conn, dana: dana, organization: organization, page: page} = ctx
      conn = log_in_user(conn, dana)
      {:ok, lv, _html} = live(conn, ~p"/orgs/wsara/forms/new")

      start(lv, "debrief.pdf", page)

      {:ok, lv, html} =
        lv
        |> form("#form-start", %{"name" => "Incident debrief"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Incident debrief added."
      assert has_element?(lv, "#form-not-written")

      assert %Form{text: ""} =
               Repo.get_by!(Form, organization_id: organization.id, name: "Incident debrief")
    end

    test "are a 404 for anyone else", %{conn: conn, form: form} do
      conn = log_in_user(conn, user_fixture())
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/new") end
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/#{form}/edit") end
    end

    test "with AI writing open, Change form tries it on Coast Range SAR, and a fix by hand saves",
         %{conn: conn, dana: dana, form: form} do
      {:ok, _settings} =
        SetAISettings.call(
          %{access: "everyone", model: "claude-sonnet-5-5", monthly_budget: "50"},
          make_admin(user_fixture())
        )

      conn = log_in_user(conn, dana)
      {:ok, lv, _html} = live(conn, ~p"/orgs/wsara/forms/#{form}")
      assert has_element?(lv, "#form-change[href='/orgs/wsara/forms/#{form.id}/edit']")

      {:ok, lv, _html} = live(conn, ~p"/orgs/wsara/forms/#{form}/edit")
      render_async(lv, 5_000)
      assert has_element?(lv, "label[for='form-try-activity']", "Tried on Coast Range SAR")
      assert has_element?(lv, "#form-try-activity option", "Missing hiker")
      refute has_element?(lv, "#form-try-open")
      assert has_element?(lv, "#form-ai", "every team in WSARA has")

      lv |> element("#form-show-text") |> render_click()
      fixed = String.replace(@text, "ask notes 'Notes'", "ask notes 'Anything else'")
      lv |> form("#form-text-form", text: fixed) |> render_change()
      render_async(lv, 5_000)

      {:ok, lv, _html} = lv |> element("#form-save") |> render_click() |> follow_redirect(conn)
      assert render(lv) =~ "Task report saved."
      assert %Form{version: 2, text: text} = Repo.reload!(form)
      assert text =~ "Anything else"
    end
  end

  # Valley SAR, in WSARA, with team forms on and its own Debrief. Alex manages it.
  describe "a team's own forms (#1083)" do
    setup %{team: team, page: page} do
      team =
        team |> Ecto.Changeset.change(forms_enabled: true) |> Repo.update!()

      manager = manager_fixture(team)

      %{
        team: team,
        own: form_fixture(team, %{name: "Debrief", page: page}),
        alex: user_fixture(%{email: manager.email})
      }
    end

    defp team_path(team, rest \\ ""), do: "/teams/#{team.subdomain}/settings/forms#{rest}"

    test "lists the team's forms only, on Team settings' Forms tab after Fields", ctx do
      %{conn: conn, team: team, own: own, form: form, alex: alex} = ctx
      {:ok, lv, _html} = conn |> log_in_user(alex) |> live(team_path(team))

      assert has_element?(lv, "#form-#{own.id}-name[href='#{team_path(team, "/#{own.id}")}']")
      assert has_element?(lv, "#form-#{own.id}-state", "Off")
      refute has_element?(lv, "#form-#{form.id}-name")
      assert has_element?(lv, "th", "On activities")
      assert has_element?(lv, "nav a[href='#{team_path(team)}'][aria-current]", "Forms")
      refute has_element?(lv, "#side-nav-forms")
      refute has_element?(lv, "#upload-form")
      assert has_element?(lv, "#new-form")

      tabs = team |> TeamSettingsTabs.list() |> Enum.map(& &1.key)
      assert Enum.at(tabs, Enum.find_index(tabs, &(&1 == :fields)) + 1) == :forms
    end

    test "Delete form deletes a form no PDF was published from, and goes back to Forms",
         ctx do
      %{conn: conn, team: team, own: own, alex: alex} = ctx
      conn = log_in_user(conn, alex)
      {:ok, lv, _html} = live(conn, team_path(team, "/#{own.id}"))

      assert has_element?(lv, "#form-actions #form-delete[data-confirm-button='Delete form']")

      {:ok, lv, html} = lv |> element("#form-delete") |> render_click() |> follow_redirect(conn)

      assert html =~ "Deleted Debrief."
      refute has_element?(lv, "#form-#{own.id}-name")
      refute Repo.get(Form, own.id)
    end

    test "no Delete form once a PDF was published from it", ctx do
      %{conn: conn, team: team, own: own, alex: alex} = ctx

      team
      |> member_fixture()
      |> tax_credit_letter_fixture()
      |> Ecto.Changeset.change(form_id: own.id)
      |> Repo.update!()

      {:ok, lv, _html} = conn |> log_in_user(alex) |> live(team_path(team, "/#{own.id}"))
      refute has_element?(lv, "#form-delete")
    end

    test "are a 404 while team forms are off, with no Forms tab", ctx do
      %{conn: conn, team: team, own: own, alex: alex} = ctx
      team |> Ecto.Changeset.change(forms_enabled: false) |> Repo.update!()
      conn = log_in_user(conn, alex)

      {:ok, lv, _html} = live(conn, "/teams/#{team.subdomain}/settings/fields")
      refute has_element?(lv, "nav a[href='#{team_path(team)}']")

      assert_raise Web.Status.NotFound, fn -> live(conn, team_path(team)) end
      assert_raise Web.Status.NotFound, fn -> live(conn, team_path(team, "/#{own.id}")) end
      assert_error_sent 404, fn -> get(conn, team_path(team, "/#{own.id}/page")) end
    end

    test "its team admin sets it testing, and sees there's no activity to try it on", ctx do
      %{conn: conn, team: team, own: own, alex: alex} = ctx
      {:ok, lv, _html} = conn |> log_in_user(alex) |> live(team_path(team, "/#{own.id}"))

      assert has_element?(lv, "#form-on-hint", "Only Valley SAR sees it")
      lv |> element("#form-on") |> render_click()
      assert Repo.reload!(own).state == :testing
      assert has_element?(lv, "#form-state", "Testing")
      assert Repo.get_by!(Event, kind: :form_set_testing).team_id == team.id

      assert has_element?(lv, "#form-try-none", "Your team has no activity this form shows on.")
      refute has_element?(lv, "#form-replace")
    end

    test "opens its blank page", %{conn: conn, team: team, own: own, alex: alex, page: page} do
      conn = conn |> log_in_user(alex) |> get(team_path(team, "/#{own.id}/page"))
      assert response(conn, 200) == page
    end

    test "another team's form is a 404, as is its organization's", ctx do
      %{conn: conn, team: team, form: form, alex: alex} = ctx
      other = form_fixture(team_fixture())
      conn = log_in_user(conn, alex)

      for id <- [other.id, form.id] do
        assert_raise Web.Status.NotFound, fn -> live(conn, team_path(team, "/#{id}")) end
        assert_error_sent 404, fn -> get(conn, team_path(team, "/#{id}/page")) end
      end
    end

    test "has no Replace, even for a SAR Duty admin: AI writing writes it (#1089)", ctx do
      %{conn: conn, team: team, own: own} = ctx
      conn = log_in_user(conn, sar_duty_admin())
      {:ok, lv, _html} = live(conn, team_path(team, "/#{own.id}"))

      refute has_element?(lv, "#form-replace")

      assert conn |> get(team_path(team, "/#{own.id}/replace")) |> html_response(404)
    end

    test "its team admin starts one from the agency's PDF, not written yet", ctx do
      %{conn: conn, team: team, alex: alex, page: page} = ctx
      conn = log_in_user(conn, alex)
      {:ok, lv, _html} = live(conn, team_path(team))
      assert has_element?(lv, "#new-form[href='#{team_path(team, "/new")}']")

      {:ok, lv, _html} = live(conn, team_path(team, "/new"))
      lv |> form("#form-start", %{"name" => "Task report"}) |> render_change()
      start(lv, "task_report.pdf", page)
      lv |> form("#form-start", %{"name" => "Task report"}) |> render_submit()
      assert has_element?(lv, "#form-start", "WSARA has a form called Task report.")

      start(lv, "task_report.pdf", page)

      {:ok, lv, _html} =
        lv
        |> form("#form-start", %{"name" => "Incident debrief"})
        |> render_submit()
        |> follow_redirect(conn)

      started = Repo.get_by!(Form, team_id: team.id, name: "Incident debrief")
      refute Form.written?(started)
      assert started.state == :off
      assert Form.page_bytes(started) == page

      assert has_element?(lv, "#form-state", "Not written yet")
      assert has_element?(lv, "#form-not-written", "Incident debrief isn't written yet.")
      refute has_element?(lv, "#form-on")
      refute has_element?(lv, "#form-try")
      refute has_element?(lv, "#form-text")
      refute has_element?(lv, "#form-replace")
    end

    test "a scan has no text to read, so it can't start a form", ctx do
      %{conn: conn, team: team, alex: alex} = ctx
      {:ok, scan} = Service.Typst.compile("#rect(width: 2in, height: 1in, fill: gray)")
      {:ok, lv, _html} = conn |> log_in_user(alex) |> live(team_path(team, "/new"))

      start(lv, "scan.pdf", scan)
      lv |> form("#form-start", %{"name" => "Incident debrief"}) |> render_submit()

      assert has_element?(lv, "#form-start", "This PDF is a scan")
      refute Repo.get_by(Form, team_id: team.id, name: "Incident debrief")
    end
  end

  defp start(lv, filename, content) do
    lv
    |> file_input("#form-start", :page, [
      %{name: filename, content: content, type: "application/pdf"}
    ])
    |> render_upload(filename)
  end

  defp ids(html), do: Regex.run(~r/value="(\d+)"/, html, capture: :all_but_first)
end
