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

  test "only a SAR Duty admin saves one", %{organization: organization, page: page} do
    user = user_fixture()
    organization_admin_fixture(organization, user.email)

    assert SaveForm.call(organization, nil, @text, page, user) == {:error, :forbidden}
    assert Form.get_all(organization) == []
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
