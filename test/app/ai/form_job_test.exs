defmodule App.AI.FormJobTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AI.FormJob
  alias App.AI.Tool.CheckForm
  alias App.Model.AISettings
  alias App.Model.Form
  alias App.Operation.AskAI

  @now ~U[2026-11-15 18:00:00Z]
  @text File.read!("test/support/fixtures/forms/task_report.txt")
  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup_all do
    {:ok, page} = Service.Typst.compile(@page_source)
    %{page: page}
  end

  # A team with the fields the test form reads, its people, and an incident.
  setup %{page: page} do
    team = team_fixture(%{name: "Fraser Valley SAR"})

    custom_field_fixture(team, %{
      title: "What was SAR tasked to do?",
      field_type: "single_choice",
      options: [%{"id" => 1, "label" => "Search - lost subject(s)"}]
    })

    custom_field_fixture(team, %{title: "People helped", field_type: "number"})
    form = form_fixture(team, %{name: "Debrief", text: "", page: page})
    %{team: team, form: form}
  end

  # The one rule (#816), for forms (#1089): the request carries the agency's blank form
  # and how the team is organized, never who is in it or what they did. The incident
  # the page tries the form on never reaches it.
  test "the request has the page and the team's fields, and none of its records",
       %{team: team, form: form, page: page} do
    member =
      member_fixture(team, %{
        name: "Avery Quillfeather",
        email: "avery.quillfeather@example.com",
        phone: "604-555-0199",
        address: "4417 Larkspur Lane"
      })

    activity =
      activity_fixture(team, %{
        title: "Swiftwater callout at Hope",
        activity_kind: "incident",
        description: "Two kayakers found on the far shore",
        address: "99 Trailhead Way",
        tracking_number: "PROS-2026-99881"
      })

    attendance_fixture(activity, member)
    group_fixture(team, %{title: "Rope rescue team"})

    earlier = [
      %{
        ask: "Write this form.",
        note: "Wrote it.",
        blank: [%{label: "Injured", why: "No field."}]
      }
    ]

    job = FormJob.build(team, form, page, @text, "tick Search for a search", @now, earlier)
    request = AskAI.request(%AISettings{model: "claude-sonnet-5-5"}, job, [prompt(job)])
    sent = Jason.encode!(request)

    assert sent =~ "Rope rescue team"
    assert sent =~ "People helped"
    assert sent =~ "tick Search for a search"
    assert sent =~ "You left blank: Injured"
    assert sent =~ "task_number text top 112pt"

    [document, measures, _now] = job.prompt
    assert document["source"]["data"] == Base.encode64(page)
    assert measures["text"] =~ "The page's measures"
    assert measures["cache_control"]

    secrets = [
      member.name,
      member.email,
      member.phone,
      member.address,
      member.ref_id,
      activity.title,
      activity.description,
      activity.address,
      activity.tracking_number,
      activity.ref_id
    ]

    for value <- secrets, value not in [nil, ""] do
      refute sent =~ value, "the request holds #{value}"
    end

    assert job.stream
    assert job.kind == :form
  end

  test "the rules and the language come first, so they cache for every team",
       %{team: team, form: form, page: page} do
    job = FormJob.build(team, form, page, "", "Write this form.", @now)
    [shared, own] = job.system

    assert shared =~ "You write a form in SAR Duty"
    assert shared =~ "### Writing a team's form"
    assert shared =~ "## Subjects"
    refute shared =~ team.name
    assert own =~ team.name

    [_document, _measures, now] = job.prompt
    assert now["text"] =~ "none yet: write its first draft"
  end

  test "an answer is checked as saving would, with what it left blank",
       %{team: team, form: form, page: page} do
    finish = FormJob.build(team, form, page, "", "Write this form.", @now).finish
    text = @text |> String.replace("form 'Task report'", "form 'Debrief'") |> String.trim()

    assert {:ok,
            %{
              text: ^text,
              note: "Wrote it.",
              blank: [%{label: "Signature", why: "Signed by hand."}]
            }} =
             finish.(%{
               "text" => text,
               "note" => "Wrote it.",
               "blank" => [%{"label" => "Signature", "why" => "Signed by hand."}]
             })

    assert {:retry, mistake} =
             finish.(%{
               "text" => "form 'Debrief'\nplaces\n  nowhere",
               "note" => "",
               "blank" => []
             })

    assert is_binary(mistake)

    assert {:unchanged, "Nothing to add."} =
             finish.(%{"text" => "", "note" => "Nothing to add.", "blank" => []})
  end

  test "check_form checks a text as saving would, and saves nothing",
       %{team: team, form: form, page: page} do
    context = %{owner: team, now: @now, form: form, page: page}
    text = String.replace(@text, "form 'Task report'", "form 'Debrief'")

    assert {:ok, %{"ok" => true, "asks" => asks, "places" => places}} =
             CheckForm.call(context, %{"text" => text})

    assert "Task leader" in asks
    assert "task_number" in places
    assert Repo.reload!(form).text == ""

    assert {:error, message} =
             CheckForm.call(context, %{
               "text" => String.replace(text, "`People helped`", "`Nobody`")
             })

    assert message =~ "Nobody"
    assert CheckForm.call(context, %{}) == {:error, "Give text as the form's whole text."}
    assert %Form{} = form
  end

  # An organization's form must hold on every team in it, so AI gets only the custom
  # fields they all have, and no team's own.
  test "an organization's form names its teams, and only the fields they all have",
       %{team: team, page: page} do
    other = team_fixture(%{name: "Harrison SAR"})
    custom_field_fixture(other, %{title: "People helped", field_type: "number"})
    custom_field_fixture(other, %{title: "Harrison only", field_type: "text"})
    organization = organization_fixture([team, other], %{name: "Valley SAR Association"})
    form = form_fixture(organization, %{name: "Debrief", text: "", page: page})

    [_shared, own] = FormJob.build(organization, form, page, "", "Write this form.", @now).system

    assert own =~ "Valley SAR Association's, for every team in it"
    assert own =~ "Fraser Valley SAR, Harrison SAR"
    refute own =~ "Harrison only"
    refute own =~ "What was SAR tasked to do?"
  end

  defp prompt(job), do: %{"role" => "user", "content" => job.prompt}
end
