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

  defp claude_response(request, agent) do
    case List.last(request["messages"]) do
      %{"content" => [%{"type" => "tool_result"} | _]} ->
        Agent.get_and_update(agent, fn [answer | rest] -> {answer(answer), rest ++ [answer]} end)

      %{"content" => content} when is_binary(content) ->
        # SAR Duty's check sent it back: answer again with the same.
        Agent.get(agent, fn [answer | _] -> answer(answer) end)

      _first ->
        text = Agent.get(agent, fn [answer | _] -> answer["text"] end)

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

    render_async(lv)

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
    assert has_element?(lv, "#form-page-1[alt='Page 1 of 2, marked SAMPLE']")

    # The text is folded, and read only.
    refute has_element?(lv, "#form-text-code")
    lv |> element("#form-show-text") |> render_click()
    assert has_element?(lv, "#form-text-code", "form 'Debrief'")
    refute has_element?(lv, "#form-text textarea")

    # Nothing is saved until Save form, a reload asks nothing, and the conversation goes.
    refute Form.written?(Repo.reload!(form))
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
    assert has_element?(lv, "#form-ai #form-ai-form", "Describe a change")
    assert has_element?(lv, "#form-ai", "AI works only with the agency's blank form")
    assert has_element?(lv, "#form-ai-agents-link[href='/agents']")

    lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
    render_async(lv)
    lv |> form("#form-ai-form", ai: %{ask: "Call Notes Anything else"}) |> render_submit()
    render_async(lv)

    requests = for {:claude, request} <- messages(), do: request
    last = List.last(requests)
    [_document, _measures, now] = hd(last["messages"])["content"]
    assert now["text"] =~ "Earlier asks in this visit"
    assert now["text"] =~ "- The admin asked: Write this form.\n  You noted: Wrote it."

    lv |> element("#form-show-text") |> render_click()
    assert has_element?(lv, "#form-text-code", "Anything else")

    [_, id] = Regex.run(~r/id="form-ai-undo-(\d+)"/, render(lv))
    lv |> element("#form-ai-undo-#{id}") |> render_click()
    refute has_element?(lv, "#form-ai-asks")
    refute has_element?(lv, "#form-text")
    assert has_element?(lv, "#form-blank-page")
  end

  test "Save form saves the text and keeps the form's state", ctx do
    %{conn: conn, team: team, alex: alex, started: started} = ctx
    stub_claude([%{"text" => written(), "note" => "Wrote it.", "blank" => []}])
    conn = log_in_user(conn, alex)
    {:ok, lv, _html} = live(conn, forms_path(team, "/#{started.id}/edit"))

    lv |> form("#form-ai-form", ai: %{ask: "Write this form."}) |> render_submit()
    render_async(lv)

    {:ok, lv, _html} = lv |> element("#form-save") |> render_click() |> follow_redirect(conn)
    assert render(lv) =~ "Incident debrief saved."

    form = Repo.reload!(started)
    assert form.text == String.trim(written())
    assert form.state == :off
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
    assert has_element?(lv, "#ai_ask", "Write this form.")
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
    render_async(lv)

    assert render(lv) =~ "Its text still had a mistake:"
    assert has_element?(lv, "#ai_ask", "Write this form.")
    refute has_element?(lv, "#form-text")
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
