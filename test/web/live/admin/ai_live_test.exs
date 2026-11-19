defmodule Web.Admin.AILiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AIAsk
  alias App.Model.AISettings
  alias App.Model.Event

  test "a SAR Duty admin sets who gets it, the models, next asks, and the budget, and sees the month",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    admin = make_admin(user)

    AIAsk.record!(
      team_id: team.id,
      user_id: admin.id,
      kind: :report,
      ask: "hours per member this year",
      model: "claude-sonnet-5-5",
      input_tokens: 1_000,
      cache_write_tokens: 8_000,
      output_tokens: 2_000,
      cost_microdollars: 42_000,
      turns: 2,
      duration_ms: 9_500,
      outcome: :used,
      asked_at: DateTime.utc_now()
    )

    AIAsk.record!(
      team_id: team.id,
      user_id: admin.id,
      kind: :report,
      ask: "add a menu for the period",
      model: "claude-sonnet-5-5",
      input_tokens: 9_000,
      cost_microdollars: 18_000,
      outcome: :stopped,
      asked_at: DateTime.utc_now()
    )

    form =
      AIAsk.record!(
        team_id: team.id,
        user_id: admin.id,
        kind: :form,
        ask: "Write this form.",
        model: "claude-sonnet-5-5",
        input_tokens: 30_000,
        cost_microdollars: 20_000,
        outcome: :used,
        asked_at: DateTime.utc_now()
      )

    line =
      AIAsk.record!(
        team_id: team.id,
        user_id: admin.id,
        kind: :history_line,
        ask: "Members",
        model: "claude-sonnet-5-5",
        input_tokens: 900,
        cost_microdollars: 2_000,
        outcome: :used,
        asked_at: DateTime.utc_now()
      )

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin/ai")

    assert has_element?(lv, "#ai-month-spent", "$0.08 of $50.00 · 3 asks, 1 History line")
    assert has_element?(lv, "#ai-team-#{team.id}", "$0.08")
    assert has_element?(lv, "#ai-team-#{team.id} td[data-label=Asks]", "3")
    assert has_element?(lv, "#ai-ask-#{form.id}", "Claude Sonnet 5.5 · form · used")
    assert has_element?(lv, "#ai-asks", "hours per member this year")
    assert has_element?(lv, "#ai-asks", "add a menu for the period")
    assert has_element?(lv, "#ai-asks", "Claude Sonnet 5.5 · report · stopped")
    assert has_element?(lv, "#ai-ask-#{line.id}", "History line: Members")
    assert has_element?(lv, "#ai-ask-#{line.id}", "History line at save")
    refute has_element?(lv, "#ai-not-set-up")

    # Each model's price shows under it, and follows a change before Save.
    assert has_element?(lv, "#ai-settings", "$2.00 in, $10.00 out per million tokens.")
    assert has_element?(lv, "#ai-settings", "$4.00 in, $20.00 out per million tokens.")

    lv
    |> form("#ai-settings", settings: %{form_model: "claude-sonnet-5-5"})
    |> render_change()

    refute has_element?(lv, "#ai-settings", "$4.00 in")

    lv
    |> form("#ai-settings",
      settings: %{
        access: "everyone",
        report_model: "claude-opus-5-5",
        form_model: "claude-sonnet-5-5",
        report_next_asks: "4",
        form_next_asks: "0",
        monthly_budget: "75",
        asks_per_day: "40"
      }
    )
    |> render_submit()

    settings = AISettings.get()
    assert settings.access == "everyone"
    assert settings.report_model == "claude-opus-5-5"
    assert settings.form_model == "claude-sonnet-5-5"
    assert settings.report_next_asks == 4
    assert settings.form_next_asks == 0
    assert settings.monthly_budget_cents == 7_500
    assert settings.asks_per_day == 40
    assert Event.get_last(:ai_settings_changed).user_id == admin.id
  end

  test "only SAR Duty admins open it", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    assert_raise Web.Status.NotFound, fn -> conn |> log_in_user(user) |> live(~p"/admin/ai") end
  end
end
