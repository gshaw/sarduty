defmodule Web.Components.StatSwitchTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Web.Components.StatSwitch

  test "stat_switch/1 marks the current count, formats counts, and greys a zero" do
    assigns = %{}

    document =
      ~H"""
      <.stat_switch label="Kind">
        <:view id="all" patch="/a" current={true} count={1212}>All</:view>
        <:view id="incidents" patch="/b" count={0} marker="incident">Incidents</:view>
      </.stat_switch>
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()

    count = fn selector -> document |> LazyHTML.query(selector) |> Enum.count() end

    assert count.(~s(nav.stat-switch[aria-label="Kind"])) == 1
    assert count.(~s(#all[aria-current="page"])) == 1
    assert count.(~s(#incidents[aria-current])) == 0
    assert document |> LazyHTML.query("#all .stat-switch-value") |> LazyHTML.text() == "1,212"
    assert count.("#incidents.is-zero") == 1
    assert count.("#incidents .marker.marker-incident") == 1
  end
end
