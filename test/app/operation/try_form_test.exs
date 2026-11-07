defmodule App.Operation.TryFormTest do
  # Prints on Coast Range SAR's own database (App.SampleRepo), which only reads; the
  # form and its page are in App.Repo's sandbox.
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Operation.TryForm

  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup do
    {:ok, page} = Service.Typst.compile(@page_source)
    %{form: form_fixture(organization_fixture(), %{page: page})}
  end

  test "lists Coast Range SAR's activities it shows on, newest first", %{form: form} do
    activities = TryForm.activities(form)

    assert activities != []
    assert Enum.all?(activities, &(&1.activity_kind == "incident"))
    assert activities == Enum.sort_by(activities, & &1.started_at, {:desc, DateTime})
    # Missing hiker is the newest, a draft; a try starts on the newest published one.
    assert hd(activities).title == "Missing hiker"
    assert TryForm.first(activities).is_published
  end

  test "prints it on one of them, marked SAMPLE", %{form: form} do
    activity = form |> TryForm.activities() |> TryForm.first()

    assert {:ok, %{content: "%PDF" <> _, title: title}} = TryForm.call(form, activity.id)
    assert title == "Task report #{activity.ref_id}"
  end

  test "refuses an activity the form doesn't show on", %{form: form} do
    assert TryForm.call(form, -1) == {:error, "This form is not for this activity."}
  end

  test "a form that doesn't read on Coast Range SAR lists nothing", %{form: form} do
    form = %{form | text: String.replace(form.text, "`People helped`", "`People halped`")}
    assert TryForm.activities(form) == []
  end
end
