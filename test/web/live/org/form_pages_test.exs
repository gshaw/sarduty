defmodule Web.Org.FormPagesTest do
  use Web.ConnCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias App.Model.Event
  alias App.Model.Form
  alias App.Repo

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
      refute has_element?(lv, "#upload-form")
    end

    test "says who uploads them when there are none", %{conn: conn, dana: dana, form: form} do
      Repo.delete!(form)
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/forms")
      assert has_element?(lv, "#no-forms", "A SAR Duty site admin uploads WSARA's forms.")
    end

    test "a SAR Duty admin uploads one", %{conn: conn} do
      {:ok, lv, _html} = conn |> log_in_user(sar_duty_admin()) |> live(~p"/orgs/wsara/forms")
      assert has_element?(lv, "#upload-form")
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

    test "its organization admin turns it on and off", %{conn: conn, dana: dana, form: form} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/forms/#{form}")

      lv |> element("#form-on") |> render_click()
      assert Repo.reload!(form).enabled
      assert has_element?(lv, "#form-state", "On")

      lv |> element("#form-off") |> render_click()
      refute Repo.reload!(form).enabled

      kinds = [:form_turned_on, :form_turned_off]
      assert [_on, _off] = Event |> where([e], e.kind in ^kinds) |> Repo.all()
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

  describe "Upload form and Replace form" do
    test "are for SAR Duty admins only", %{conn: conn, dana: dana, form: form} do
      conn = log_in_user(conn, dana)
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/new") end
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/wsara/forms/#{form}/edit") end
    end

    test "a SAR Duty admin uploads the text and page",
         %{conn: conn, form: form, organization: organization, page: page} do
      Repo.delete!(form)
      conn = log_in_user(conn, sar_duty_admin())
      {:ok, lv, _html} = live(conn, ~p"/orgs/wsara/forms/new")

      upload(lv, :text, "task_report.txt", @text, "text/plain")
      upload(lv, :page, "task_report.pdf", page, "application/pdf")

      {:ok, lv, _html} = lv |> form("#form-upload") |> render_submit() |> follow_redirect(conn)

      [form] = Form.get_all(organization)
      assert form.version == 1
      assert has_element?(lv, "#form-version", "1")
    end

    test "names what's wrong under its file, and keeps the other", %{conn: conn, form: form} do
      {:ok, lv, _html} =
        conn |> log_in_user(sar_duty_admin()) |> live(~p"/orgs/wsara/forms/#{form}/edit")

      text = String.replace(@text, "`People helped`\n", "`People halped`\n")
      upload(lv, :text, "task_report.txt", text, "text/plain")
      lv |> form("#form-upload") |> render_submit()

      assert has_element?(lv, "#form-text-file", "Valley SAR: Line 10:")
      assert has_element?(lv, "#form-text-kept")
      assert Repo.reload!(form).version == 1

      # The kept text is the one that fails; the page stays the form's.
      lv |> form("#form-upload") |> render_submit()
      assert has_element?(lv, "#form-text-file", "Valley SAR: Line 10:")
    end

    test "replacing keeps the page and raises the version", %{conn: conn, form: form, page: page} do
      {:ok, lv, _html} =
        conn |> log_in_user(sar_duty_admin()) |> live(~p"/orgs/wsara/forms/#{form}/edit")

      upload(lv, :text, "task_report.txt", @text, "text/plain")
      lv |> form("#form-upload") |> render_submit()

      form = Repo.reload!(form)
      assert form.version == 2
      assert Form.page_bytes(form) == page
    end
  end

  defp upload(lv, name, filename, content, type) do
    lv
    |> file_input("#form-upload", name, [%{name: filename, content: content, type: type}])
    |> render_upload(filename)
  end

  defp ids(html), do: Regex.run(~r/value="(\d+)"/, html, capture: :all_but_first)
end
