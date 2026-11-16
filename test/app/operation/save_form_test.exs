defmodule App.Operation.SaveFormTest do
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.Form
  alias App.Operation.SaveForm

  @text File.read!("test/support/fixtures/forms/task_report.txt")
  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup_all do
    {:ok, page} = Service.Typst.compile(@page_source)
    %{page: page}
  end

  # An organization whose one team has the fields the test form reads, as a BC team has
  # BCSARA's. Coast Range SAR has them too.
  setup do
    team = team_fixture(%{name: "Valley SAR"})

    custom_field_fixture(team, %{
      title: "What was SAR tasked to do?",
      field_type: "single_choice",
      options: [%{"id" => 1, "label" => "Search - lost subject(s)"}]
    })

    custom_field_fixture(team, %{title: "People helped", field_type: "number"})

    %{
      team: team,
      organization: organization_fixture([team], %{short_name: "WSARA"}),
      admin: user_fixture(%{is_admin: true})
    }
  end

  test "a SAR Duty admin uploads a form: its name and about come from the text",
       %{organization: organization, admin: admin, page: page} do
    assert {:ok, form} = SaveForm.call(organization, nil, @text, page, admin)

    assert %Form{name: "Task report", version: 1, state: :off} = form
    assert form.about == "A made-up agency's task report, for tests."
    assert form.user_id == admin.id
    assert form.page_sha256 == Form.sha256(page)
    assert Form.page_bytes(form) == page
    assert [%Form{}] = Form.get_all(organization)

    assert %Event{data: %{"form_id" => form_id, "version" => 1}} =
             Repo.get_by!(Event, kind: :form_saved)

    assert form_id == form.id
  end

  test "replacing it raises its version, and keeps its page when none comes",
       %{organization: organization, admin: admin, page: page} do
    {:ok, form} = SaveForm.call(organization, nil, @text, page, admin)
    text = String.replace(@text, "for tests.", "for tests, again.")

    assert {:ok, replaced} = SaveForm.call(organization, form, text, nil, admin)

    assert replaced.id == form.id
    assert replaced.version == 2
    assert replaced.about == "A made-up agency's task report, for tests, again."
    assert Form.page_bytes(replaced) == page
  end

  test "its organization admins and SAR Duty admins save one, and nobody else (#1089)",
       %{organization: organization, page: page} do
    org_admin = user_fixture()
    organization_admin_fixture(organization, org_admin.email)
    other = user_fixture()
    organization_admin_fixture(organization_fixture(), other.email)

    for user <- [user_fixture(), other] do
      assert SaveForm.call(organization, nil, @text, page, user) == {:error, :forbidden}
    end

    assert Form.get_all(organization) == []
    assert {:ok, %Form{}} = SaveForm.call(organization, nil, @text, page, org_admin)
  end

  test "its organization admins start one from the agency's PDF (#1089)",
       %{organization: organization, page: page} do
    org_admin = user_fixture()
    organization_admin_fixture(organization, org_admin.email)

    assert {:ok, %Form{text: "", organization_id: id, name: "Debrief"}} =
             SaveForm.start(organization, "Debrief", page, org_admin)

    assert id == organization.id

    assert {:error, :name, "WSARA has a form called Debrief. Give this one another name."} =
             SaveForm.start(organization, "Debrief", page, org_admin)
  end

  test "a form from another organization isn't replaced here",
       %{organization: organization, admin: admin, page: page} do
    form = form_fixture(organization_fixture())
    assert SaveForm.call(organization, form, @text, page, admin) == {:error, :forbidden}
  end

  test "names the team whose fields the form reads and it lacks",
       %{organization: organization, admin: admin, page: page} do
    %{name: "Alpine SAR"}
    |> team_fixture()
    |> Ecto.Changeset.change(organization_id: organization.id)
    |> Repo.update!()

    assert {:error, :text, "Alpine SAR: Line 9: " <> _rest} =
             SaveForm.call(organization, nil, @text, page, admin)
  end

  test "refuses a team's RESTRICTED field: it's the team's alone",
       %{organization: organization, admin: admin, page: page, team: team} do
    custom_field_fixture(team, %{title: "Debrief", restricted: true})
    text = String.replace(@text, "`People helped`\n", "`People helped`, `Debrief`\n")

    assert {:error, :text, "Valley SAR: Line 10: " <> _rest} =
             SaveForm.call(organization, nil, text, page, admin)
  end

  test "every expect must hold", %{organization: organization, admin: admin, page: page} do
    text =
      String.replace(@text, "description = 'Found on the ridge. Walked", "description = 'Walked")

    assert {:error, :text, message} = SaveForm.call(organization, nil, text, page, admin)
    assert message =~ "Line 69:"
  end

  test "checks the page", %{organization: organization, admin: admin, page: page} do
    assert SaveForm.call(organization, nil, @text, nil, admin) ==
             {:error, :page, "Upload the form's page. Its text says page."}

    assert SaveForm.call(organization, nil, @text, "not a PDF", admin) ==
             {:error, :page, "SAR Duty cannot read this form's page. Upload it as a PDF."}

    text = String.replace(@text, "size 9pt, page 2", "size 9pt, page 3")

    assert SaveForm.call(organization, nil, text, page, admin) ==
             {:error, :page, "Place err is on page 3. The form's page has 2 pages."}
  end

  test "a document isn't a form", %{organization: organization, admin: admin, page: page} do
    text = String.replace(@text, "form 'Task report'", "document 'Task report'")

    assert {:error, :text, message} = SaveForm.call(organization, nil, text, page, admin)
    assert message =~ "form"
  end

  test "two forms can't share a name", %{organization: organization, admin: admin, page: page} do
    {:ok, _form} = SaveForm.call(organization, nil, @text, page, admin)

    assert SaveForm.call(organization, nil, @text, page, admin) ==
             {:error, :text, "WSARA has a form called Task report. Replace that one instead."}
  end

  describe "a team's own form (#1083)" do
    setup %{team: team}, do: %{team: Repo.reload!(team)}

    test "is the team's, checked on that team alone, RESTRICTED fields and all",
         %{team: team, organization: organization, admin: admin, page: page} do
      custom_field_fixture(team, %{title: "Debrief", restricted: true})
      text = String.replace(@text, "`People helped`\n", "`People helped`, `Debrief`\n")

      # A team in the organization without the form's fields doesn't matter to it.
      %{name: "Alpine SAR"}
      |> team_fixture()
      |> Ecto.Changeset.change(organization_id: organization.id)
      |> Repo.update!()

      assert {:ok, %Form{team_id: team_id, organization_id: nil} = form} =
               SaveForm.call(team, nil, text, page, admin)

      assert team_id == team.id
      assert Form.get_all(team) == [form]
      assert Form.get_all(organization) == []

      assert %Event{team_id: ^team_id, data: %{"team_id" => ^team_id}} =
               Repo.get_by!(Event, kind: :form_saved)
    end

    test "can't take the name of one of its organization's forms",
         %{team: team, organization: organization, admin: admin, page: page} do
      form_fixture(organization)

      assert SaveForm.call(team, nil, @text, page, admin) ==
               {:error, :text, "WSARA has a form called Task report. Give yours another name."}
    end

    test "two of the team's forms can't share a name", %{team: team, admin: admin, page: page} do
      {:ok, _form} = SaveForm.call(team, nil, @text, page, admin)

      assert SaveForm.call(team, nil, @text, page, admin) ==
               {:error, :text,
                "Your team has a form called Task report. Give this one another name."}
    end

    test "its team admins save it, and nobody else", %{team: team, page: page} do
      manager = user_fixture(%{email: manager_fixture(team).email})
      assert {:ok, %Form{}} = SaveForm.call(team, nil, @text, page, manager)

      member = user_fixture(%{email: member_fixture(team).email})
      text = String.replace(@text, "form 'Task report'", "form 'Debrief'")
      assert SaveForm.call(team, nil, text, page, member) == {:error, :forbidden}
    end

    test "starts from the agency's PDF alone, off and not written, until its first text",
         %{team: team, page: page} do
      manager = user_fixture(%{email: manager_fixture(team).email})

      assert {:ok, %Form{text: "", state: :off, version: 1} = started} =
               SaveForm.start(team, " Debrief ", page, manager)

      assert started.name == "Debrief"
      refute Form.written?(started)
      assert Form.page_bytes(started) == page

      assert SaveForm.start(team, "Debrief", page, manager) ==
               {:error, :name, "Your team has a form called Debrief. Give this one another name."}

      assert SaveForm.start(team, "", page, manager) == {:error, :name, "Give the form a name."}

      assert SaveForm.start(team, "Other", nil, manager) ==
               {:error, :page, "Choose the agency's PDF."}

      text = String.replace(@text, "form 'Task report'", "form 'Debrief'")
      assert {:ok, written} = SaveForm.call(team, started, text, nil, manager)
      assert written.version == 1
      assert Form.page_bytes(written) == page
      assert {:ok, %Form{version: 2}} = SaveForm.call(team, written, text, nil, manager)
    end

    test "check_for runs every check saving runs, and saves nothing",
         %{team: team, admin: admin, page: page} do
      {:ok, started} = SaveForm.start(team, "Debrief", page, admin)
      text = String.replace(@text, "form 'Task report'", "form 'Debrief'")

      assert {:ok, %App.Document{name: "Debrief"}} =
               SaveForm.check_for(team, started, text, page)

      refute team |> Form.get(started.id) |> Form.written?()

      assert {:error, :text, "Line 1:" <> _rest} = SaveForm.check_for(team, started, "form", page)

      {:ok, _form} = SaveForm.call(team, nil, @text, page, admin)

      assert SaveForm.check_for(team, started, @text, page) ==
               {:error, :text,
                "Your team has a form called Task report. Give this one another name."}
    end

    test "a scan can't start one", %{team: team, admin: admin} do
      {:ok, scan} = Service.Typst.compile("#rect(width: 2in, height: 1in, fill: gray)")

      assert SaveForm.start(team, "Debrief", scan, admin) ==
               {:error, :page,
                "This PDF is a scan, with no text to read. Ask the agency for its PDF."}
    end

    test "another team's form, or the organization's, isn't replaced here",
         %{team: team, organization: organization, admin: admin, page: page} do
      theirs = form_fixture(team_fixture())

      assert SaveForm.call(team, theirs, @text, page, admin) == {:error, :forbidden}

      assert SaveForm.call(team, form_fixture(organization), @text, page, admin) ==
               {:error, :forbidden}
    end
  end

  describe "a form with a layout" do
    # Its layout draws the page: there's none to upload.
    @layout_form """
    form 'Claim'
    for activity where kind = 'incident'
    report task
      select ref_id from activities where id = :activity
    fill
      ref = task.ref_id
    expect with task.ref_id = '01428': ref = '01428'
    layout
    #set page(width: 200pt, height: 100pt)
    Task #values.ref
    """

    test "saves with no page", %{organization: organization, admin: admin, page: page} do
      assert {:ok, form} = SaveForm.call(organization, nil, @layout_form, nil, admin)
      assert form.page_sha256 == nil and Form.page_bytes(form) == nil

      assert SaveForm.call(organization, nil, @layout_form, page, admin) ==
               {:error, :page, "Upload no page: the form's layout draws it."}
    end

    test "its layout must print, and a mistake names its line",
         %{organization: organization, admin: admin} do
      text = String.replace(@layout_form, "#values.ref", "#values.nothing")

      assert {:error, :text, "The layout does not print. Line 10: " <> message} =
               SaveForm.call(organization, nil, text, nil, admin)

      assert message =~ ~s|does not contain key "nothing"|
    end

    test "replacing a form on a page with one with a layout drops the page",
         %{organization: organization, admin: admin, page: page} do
      {:ok, form} = SaveForm.call(organization, nil, @text, page, admin)
      text = String.replace(@layout_form, "form 'Claim'", "form 'Task report'")

      assert {:ok, replaced} = SaveForm.call(organization, form, text, nil, admin)
      assert replaced.page_sha256 == nil and Form.page_bytes(replaced) == nil
    end
  end
end
