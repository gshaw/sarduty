defmodule Web.FormChangeLiveTest do
  # Change form (#1089): a team admin writes the team's form with AI writing. Claude is
  # stubbed with Req.Test: no test spends credit.
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AIAsk
  alias App.Model.Form
  alias App.Operation.SaveForm
  alias App.Operation.SetAISettings
  alias App.Repo

  @text File.read!("test/support/fixtures/forms/task_report.txt")

  # An ask reads the page with mutool and prints the try with Typst, slower on CI than
  # render_async's 100ms.
  @wait 5_000
  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup_all do
    {:ok, page} = Service.Typst.compile(@page_source)
    %{page: page}
  end

  # Valley SAR with team forms on, the fields the test form reads, and an incident to
  # try it on. Alex manages it. AI writing is open to every team admin.
  setup %{page: page} do
    team = team_fixture(%{name: "Valley SAR"})
    team = team |> Ecto.Changeset.change(forms_enabled: true) |> Repo.update!()

    custom_field_fixture(team, %{
      title: "What was SAR tasked to do?",
      field_type: "single_choice",
      options: [%{"id" => 1, "label" => "Search - lost subject(s)"}]
    })

    custom_field_fixture(team, %{title: "People helped", field_type: "number"})

    incident =
      activity_fixture(team, %{
        title: "Overdue kayakers on the Fraser",
        activity_kind: "incident",
        started_at: ~U[2026-11-01 18:00:00Z],
        is_published: true
      })

    alex = user_fixture(%{email: manager_fixture(team).email})
    admin = make_admin(user_fixture())

    {:ok, _settings} =
      SetAISettings.call(
        %{access: "everyone", model: "claude-sonnet-5-5", monthly_budget: "50"},
        admin
      )

    {:ok, started} = SaveForm.start(team, "Incident debrief", page, alex)
    %{team: team, alex: alex, incident: incident, started: started}
  end

  defp forms_path(team, rest), do: "/teams/#{team.subdomain}/settings/forms#{rest}"

  # The text Claude writes: the test form, named for the started one, and `change` to it.
  defp written(change \\ & &1, name \\ "Incident debrief") do
    @text |> String.replace("form 'Task report'", "form '#{name}'") |> change.()
  end

  # Claude checks the text once, then answers with it. Each request goes to the test as
  # {:claude, request}.
  defp stub_claude(answers) do
    test = self()
    {:ok, agent} = Agent.start_link(fn -> answers end)

    Req.Test.stub(App.Adapter.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      send(test, {:claude, request})
      Req.Test.json(conn, claude_response(request, agent))
    end)
  end

  defp claude_response(request, agent), do: request["messages"] |> List.last() |> reply(agent)

  # After check_form, the next answer; the last one stays for any ask after it.
  defp reply(%{"content" => [%{"type" => "tool_result"} | _]}, agent),
    do: Agent.get_and_update(agent, &next/1)

  # SAR Duty's check sent it back: answer again with the same.
  defp reply(%{"content" => content}, agent) when is_binary(content),
    do: Agent.get(agent, &answer(hd(&1)))

  defp reply(_first, agent), do: agent |> Agent.get(&hd(&1)["text"]) |> check_call()

  defp next([output]), do: {answer(output), [output]}
  defp next([output | rest]), do: {answer(output), rest}

  defp check_call(text) do
    %{
      "stop_reason" => "tool_use",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => "call_1",
          "name" => "check_form",
          "input" => %{"text" => text}
        }
      ],
      "usage" => %{"input_tokens" => 30_000, "output_tokens" => 2_000}
    }
  end

  defp answer(output) do
    %{
      "stop_reason" => "end_turn",
      "content" => [%{"type" => "text", "text" => Jason.encode!(output)}],
      "usage" => %{"input_tokens" => 900, "output_tokens" => 3_000}
    }
  end

  test "New form with AI writing: What it's for is the first ask, already running", ctx do
    %{conn: conn, team: team, alex: alex, incident: incident} = ctx

    stub_claude([
      %{
        "text" => written(& &1, "Debrief"),
        "note" => "Wrote it from the agency's page, for incidents.",
        "blank" => [%{"label" => "Signature", "why" => "The task leader signs it by hand."}]
      }
    ])

    conn = log_in_user(conn, alex)
    {:ok, lv, _html} = live(conn, forms_path(team, "/new"))

    assert has_element?(lv, "#form-start", "What it's for (optional)")
    assert has_element?(lv, "#form-start", "When it's filled in and who signs it.")
    assert has_element?(lv, "#form-start-save", "Write form")

    lv
    |> file_input("#form-start", :page, [
      %{name: "debrief.pdf", content: ctx_page(), type: "application/pdf"}
    ])
    |> render_upload("debrief.pdf")

    {:ok, lv, _html} =
      lv
      |> form("#form-start", %{
        "name" => "Debrief",
        "for" => "Our debrief after each incident. The task leader signs it."
      })
      |> render_submit()
      |> follow_redirect(conn)

    form = Repo.get_by!(Form, team_id: team.id, name: "Debrief")
    assert has_element?(lv, "#form-ai-ask-running", "Our debrief after each incident.")
    assert has_element?(lv, "#form-ai-step #form-ai-stop")
    assert has_element?(lv, "#form-blank-page")

    render_async(lv, @wait)
    # Then the try prints, beside the page.
    render_async(lv, @wait)

    assert_received {:claude, request}
    sent = Jason.encode!(request)
    assert sent =~ "Our debrief after each incident."
    assert [%{"type" => "document"} | _] = hd(request["messages"])["content"]
    refute sent =~ incident.title

    assert has_element?(lv, ".ai-you", "Our debrief after each incident.")
    assert has_element?(lv, ".ai-reply", "Wrote it from the agency's page, for incidents.")
    assert has_element?(lv, ".ai-blank", "Left blank")
    assert has_element?(lv, ".ai-blank", "The task leader signs it by hand.")
    assert has_element?(lv, "#form-try-activity option", incident.title)
    # The activity it's tried on opens in a new window, to check the form against.
    assert has_element?(
             lv,
             "#form-try-open[target=_blank][href='/teams/#{team.subdomain}/activities/#{incident.id}']"
           )

    assert has_element?(lv, "#form-page-1[alt='Page 1 of 2, marked SAMPLE']")

    # How it fills in is folded until it's shown.
    refute has_element?(lv, "#form-text-input")
    lv |> element("#form-show-text", "Show how it fills in") |> render_click()
    assert has_element?(lv, "#form-text-input", "form 'Debrief'")

    # Nothing is saved until Save form, a reload asks nothing, and the conversation goes.
    refute form |> Repo.reload!() |> Form.written?()
    {:ok, lv, _html} = live(conn, forms_path(team, "/#{form.id}/edit"))
    refute has_element?(lv, "#form-ai-asks")
    assert Repo.aggregate(AIAsk, :count) == 1
  end

  test "Change form after two asks: the second carries the first, and Undo puts it back",
       ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    first = written()
    second = written(&String.replace(&1, "ask notes 'Notes'", "ask notes 'Anything else'"))

    stub_claude([
      %{"text" => first, "note" => "Wrote it.", "blank" => []},
      %{"text" => second, "note" => "Renamed Notes to Anything else.", "blank" => []}
    ])

    {:ok, lv, _html} = conn |> log_in_user(alex) |> live(forms_path(team, "/#{started.id}/edit"))
    assert has_element?(lv, "#form-ai #form-ai-form", "Ask AI")
    assert has_element?(lv, "#form-ai", "AI sees the agency's form and your team's field names")
    assert has_element?(lv, "#form-ai-agents-link[href='/agents']")

    lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
    render_async(lv, @wait)
    lv |> form("#form-ai-form", ai: %{ask: "Call Notes Anything else"}) |> render_submit()
    render_async(lv, @wait)

    requests = for {:claude, request} <- messages(), do: request
    last = List.last(requests)
    %{"messages" => [%{"content" => [_document, _measures, now]} | _]} = last
    assert now["text"] =~ "Earlier asks in this visit"
    assert now["text"] =~ "- The admin asked: Write this form.\n  You noted: Wrote it."

    lv |> element("#form-show-text") |> render_click()
    assert has_element?(lv, "#form-text-input", "Anything else")

    [_, id] = Regex.run(~r/id="form-ai-undo-(\d+)"/, render(lv))
    lv |> element("#form-ai-undo-#{id}") |> render_click()
    refute has_element?(lv, "#form-ai-asks")
    assert has_element?(lv, "#form-blank-page")
  end

  test "Save form saves the text and keeps the form's state", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    stub_claude([%{"text" => written(), "note" => "Wrote it.", "blank" => []}])
    conn = log_in_user(conn, alex)
    {:ok, lv, _html} = live(conn, forms_path(team, "/#{started.id}/edit"))
    assert has_element?(lv, "#form-unsaved[hidden]")

    lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
    render_async(lv, @wait)
    assert has_element?(lv, "#form-unsaved:not([hidden])", "Not saved yet")

    {:ok, lv, _html} = lv |> element("#form-save") |> render_click() |> follow_redirect(conn)
    assert render(lv) =~ "Incident debrief saved."

    form = Repo.reload!(started)
    assert form.text == String.trim(written())
    assert form.state == :off
  end

  describe "a new PDF from the agency" do
    # The form written, then the agency's new page: AI fits the form to it and changes
    # nothing, as the made-up page only adds a word.
    setup %{conn: conn, team: team, alex: alex, started: started} do
      revised = String.replace(@page_source, "Page 1 of 2.", "Page 1 of 2. Revised.")
      {:ok, new_page} = Service.Typst.compile(revised)

      stub_claude([
        %{"text" => written(), "note" => "Wrote it.", "blank" => []},
        %{"text" => written(), "note" => "It fits the new page as it was.", "blank" => []}
      ])

      conn = log_in_user(conn, alex)
      {:ok, lv, _html} = live(conn, forms_path(team, "/#{started.id}/edit"))
      lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
      render_async(lv, @wait)

      lv |> element("#form-replace-pdf", "Replace PDF") |> render_click()
      assert has_element?(lv, "#form-replace-dialog", "Replace the agency's PDF?")

      lv
      |> file_input("#form-replace-form", :page, [
        %{name: "task_report_v2.pdf", content: new_page, type: "application/pdf"}
      ])
      |> render_upload("task_report_v2.pdf")

      lv |> form("#form-replace-form") |> render_submit()
      refute has_element?(lv, "#form-replace-dialog")
      render_async(lv, @wait)
      %{conn: conn, lv: lv, new_page: new_page}
    end

    test "AI fits the form to it, and Save form saves the new page", ctx do
      %{conn: conn, lv: lv, new_page: new_page, started: started} = ctx

      assert has_element?(lv, ".ai-you", "Fit the form to the agency's new PDF.")
      assert has_element?(lv, ".ai-reply", "It fits the new page as it was.")
      requests = for {:claude, request} <- messages(), do: request
      assert requests |> List.last() |> Jason.encode!() =~ Base.encode64(new_page)

      {:ok, _lv, _html} = lv |> element("#form-save") |> render_click() |> follow_redirect(conn)
      assert Repo.reload!(started).page_sha256 == Form.sha256(new_page)
    end

    test "Undo puts the old page back", %{conn: conn, lv: lv, page: page, started: started} do
      [_, id] = ~r/id="form-ai-undo-(\d+)"/ |> Regex.scan(render(lv)) |> List.last()
      lv |> element("#form-ai-undo-#{id}") |> render_click()

      {:ok, _lv, _html} = lv |> element("#form-save") |> render_click() |> follow_redirect(conn)
      assert Repo.reload!(started).page_sha256 == Form.sha256(page)
    end
  end

  test "a fix by hand is checked as it's typed, and Save form saves it", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    stub_claude([%{"text" => written(), "note" => "Wrote it.", "blank" => []}])
    conn = log_in_user(conn, alex)
    {:ok, lv, _html} = live(conn, forms_path(team, "/#{started.id}/edit"))
    lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
    render_async(lv, @wait)
    lv |> element("#form-show-text") |> render_click()

    broken = written(&String.replace(&1, "`People helped`", "`People halped`"))
    lv |> form("#form-text-form", text: broken) |> render_change()
    render_async(lv, @wait)
    assert has_element?(lv, "#form-text-form .field-error")
    assert has_element?(lv, "#form-hide-text")

    fixed = written(&String.replace(&1, "ask notes 'Notes'", "ask notes 'Anything else'"))
    lv |> form("#form-text-form", text: fixed) |> render_change()
    render_async(lv, @wait)
    refute has_element?(lv, "#form-text-form .field-error")
    render_async(lv, @wait)

    {:ok, _lv, _html} = lv |> element("#form-save") |> render_click() |> follow_redirect(conn)
    assert Repo.reload!(started).text =~ "Anything else"
  end

  test "a scan is refused in Replace PDF, and the dialog stays open", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    {:ok, scan} = Service.Typst.compile("#rect(width: 2in, height: 1in, fill: gray)")
    {:ok, lv, _html} = conn |> log_in_user(alex) |> live(forms_path(team, "/#{started.id}/edit"))

    lv |> element("#form-replace-pdf") |> render_click()

    lv
    |> file_input("#form-replace-form", :page, [
      %{name: "scan.pdf", content: scan, type: "application/pdf"}
    ])
    |> render_upload("scan.pdf")

    lv |> form("#form-replace-form") |> render_submit()
    assert has_element?(lv, "#form-replace-dialog", "This PDF is a scan")

    lv |> element("#form-replace-cancel") |> render_click()
    refute has_element?(lv, "#form-replace-dialog")
  end

  test "Stop puts the words back, and the ask counts with what it spent", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    test = self()

    Req.Test.stub(App.Adapter.Claude, fn conn ->
      send(test, :waiting)
      Process.sleep(:infinity)
      conn
    end)

    {:ok, lv, _html} = conn |> log_in_user(alex) |> live(forms_path(team, "/#{started.id}/edit"))
    lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
    assert_receive :waiting

    assert has_element?(lv, "#form-ai-ask-running", "Write this form.")
    assert has_element?(lv, "#form-ai-ask[disabled]")

    lv |> element("#form-ai-stop") |> render_click()
    assert has_element?(lv, "textarea[name='ai[ask]']", "Write this form.")
    refute has_element?(lv, "#form-ai-asks")

    ask = Repo.get_by!(AIAsk, team_id: team.id)
    assert ask.kind == :form
    assert ask.outcome == :stopped
    assert AIAsk.count_today(team, DateTime.utc_now()) == 1
  end

  test "a text that fails the checks twice keeps the form as it was", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    broken = written(&String.replace(&1, "`People helped`", "`People halped`"))
    stub_claude([%{"text" => broken, "note" => "Wrote it.", "blank" => []}])

    {:ok, lv, _html} = conn |> log_in_user(alex) |> live(forms_path(team, "/#{started.id}/edit"))
    lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
    render_async(lv, @wait)

    assert render(lv) =~ "Its text still had a mistake:"
    assert has_element?(lv, "textarea[name='ai[ask]']", "Write this form.")
    assert has_element?(lv, "#form-blank-page")
    assert Repo.get_by!(AIAsk, team_id: team.id).outcome == :refused_by_checks
  end

  test "without AI writing, New form adds the form and there's no Change form", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    admin = make_admin(user_fixture())

    {:ok, _settings} =
      SetAISettings.call(
        %{access: "admins", model: "claude-sonnet-5-5", monthly_budget: "50"},
        admin
      )

    conn = log_in_user(conn, alex)
    {:ok, lv, _html} = live(conn, forms_path(team, "/new"))
    assert has_element?(lv, "#form-start-save", "Add form")
    refute has_element?(lv, "#form-start-for")

    {:ok, lv, _html} = live(conn, forms_path(team, "/#{started.id}"))
    refute has_element?(lv, "#form-change")

    {:ok, lv, _html} = live(conn, forms_path(team, "/#{started.id}/edit"))
    assert has_element?(lv, "#form-ai-closed", "AI writing is off.")
  end

  test "the form's page links Change form for its team admin", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    {:ok, lv, _html} = conn |> log_in_user(alex) |> live(forms_path(team, "/#{started.id}"))
    assert has_element?(lv, "#form-change[href='#{forms_path(team, "/#{started.id}/edit")}']")
  end

  test "a member who isn't a team admin can't open it", ctx do
    %{conn: conn, team: team, started: started} = ctx
    stranger = user_fixture()

    assert_raise Web.Status.NotFound, fn ->
      conn |> log_in_user(stranger) |> live(forms_path(team, "/#{started.id}/edit"))
    end
  end

  defp ctx_page do
    {:ok, page} = Service.Typst.compile(@page_source)
    page
  end

  defp messages do
    receive do
      message -> [message | messages()]
    after
      0 -> []
    end
  end
end
