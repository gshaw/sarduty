defmodule Web.Admin.AILiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AIAsk
  alias App.Model.AISettings
  alias App.Model.Event

  test "a SAR Duty admin sets who gets it, the model, and the budget, and sees the month",
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

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin/ai")

    assert has_element?(lv, "#ai-month-spent", "$0.04 of $50.00")
    assert has_element?(lv, "#ai-team-#{team.id}", "$0.04")
    assert has_element?(lv, "#ai-asks", "hours per member this year")
    refute has_element?(lv, "#ai-not-set-up")

    lv
    |> form("#ai-settings",
      settings: %{access: "everyone", model: "claude-opus-5-5", monthly_budget: "75"}
    )
    |> render_submit()

    settings = AISettings.get()
    assert settings.access == "everyone"
    assert settings.model == "claude-opus-5-5"
    assert settings.monthly_budget_cents == 7_500
    assert Event.get_last(:ai_settings_changed).user_id == admin.id
  end

  test "only SAR Duty admins open it", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    assert_raise Web.Status.NotFound, fn -> conn |> log_in_user(user) |> live(~p"/admin/ai") end
  end
end
