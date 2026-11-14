defmodule App.Operation.TryFormTest do
  # An organization's form prints on Coast Range SAR's own database (App.SampleRepo),
  # which only reads; the form and its page are in App.Repo's sandbox.
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Operation.TryForm

  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup do
    {:ok, page} = Service.Typst.compile(@page_source)
    organization = organization_fixture()
    %{organization: organization, form: form_fixture(organization, %{page: page})}
  end

  test "lists Coast Range SAR's activities it shows on, newest first", ctx do
    activities = TryForm.activities(ctx.form, ctx.organization)

    assert activities != []
    assert Enum.all?(activities, &(&1.activity_kind == "incident"))
    assert activities == Enum.sort_by(activities, & &1.started_at, {:desc, DateTime})
    # Missing hiker is the newest, a draft; a try starts on the newest published one.
    assert hd(activities).title == "Missing hiker"
    assert TryForm.first(activities).is_published
  end

  test "prints it on one of them, marked SAMPLE", %{form: form, organization: organization} do
    activity = form |> TryForm.activities(organization) |> TryForm.first()

    assert {:ok, %{content: "%PDF" <> _, title: title}} =
             TryForm.call(form, organization, activity.id)

    assert title == "Task report #{activity.ref_id}"
  end

  test "refuses an activity the form doesn't show on", %{form: form, organization: organization} do
    assert TryForm.call(form, organization, -1) == {:error, "This form is not for this activity."}
  end

  test "a form that doesn't read on Coast Range SAR lists nothing", ctx do
    form = %{ctx.form | text: String.replace(ctx.form.text, "`People helped`", "`People halped`")}
    assert TryForm.activities(form, ctx.organization) == []
  end

  describe "a team's own form (#1083)" do
    @claim """
    form 'Claim'
    for activity where kind = 'incident'
    report task
      select ref_id from activities where id = :activity
    fill
      ref = task.ref_id
    layout
    #set page(width: 200pt, height: 100pt)
    Task #values.ref
    """

    setup do
      team = team_fixture()
      %{team: team, form: form_fixture(team, %{name: "Claim", text: @claim, page: nil})}
    end

    test "prints on the team's own activities, never another team's", %{team: team, form: form} do
      incident = activity_fixture(team, %{activity_kind: "incident"})
      activity_fixture(team, %{activity_kind: "exercise"})
      theirs = activity_fixture(team_fixture(), %{activity_kind: "incident"})

      assert [%{id: id}] = TryForm.activities(form, team)
      assert id == incident.id

      assert {:ok, %{content: "%PDF" <> _}} = TryForm.call(form, team, incident.id)

      assert TryForm.call(form, team, theirs.id) ==
               {:error, "This form is not for this activity."}
    end
  end
end
