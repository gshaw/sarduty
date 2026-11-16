defmodule App.AI.ReportJobTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AI.ReportJob
  alias App.Model.AISettings
  alias App.Operation.AskAI

  @now ~U[2026-11-15 18:00:00Z]

  # The one rule (#816), now that SAR Duty sends: the request carries how the team is
  # organized, never who is in it or what they did.
  test "the request has the team's names for things and none of its records" do
    team = team_fixture(%{name: "Fraser Valley SAR"})

    member =
      member_fixture(team, %{
        name: "Avery Quillfeather",
        email: "avery.quillfeather@example.com",
        phone: "604-555-0199",
        address: "4417 Larkspur Lane"
      })

    activity_fixture(team, %{title: "Swiftwater callout at Hope"})
    group_fixture(team, %{title: "Rope rescue team"})
    qualification_fixture(team, %{title: "Swiftwater technician"})

    report = %{query: "select name from members", name: "", about: ""}
    job = ReportJob.build(team, report, "hours per member this year", @now)
    request = AskAI.request(%AISettings{model: "claude-sonnet-5-5"}, job, [prompt(job)])
    sent = Jason.encode!(request)

    assert sent =~ "Rope rescue team"
    assert sent =~ "Swiftwater technician"
    assert sent =~ "hours per member this year"

    for value <- [member.name, member.email, member.phone, member.address, member.ref_id] do
      refute sent =~ value, "the request holds a member's #{value}"
    end

    refute sent =~ "Swiftwater callout at Hope"
  end

  test "the language and the rules come first, so they cache for every team" do
    team = team_fixture()
    job = ReportJob.build(team, %{query: "", name: "", about: ""}, "anything", @now)
    [shared, own] = job.system

    assert shared =~ "You write reports in SAR Duty"
    refute shared =~ team.name
    assert own =~ team.name
  end

  test "an answer is checked against the team's fields, and a new report gets a name" do
    team = team_fixture()
    report = %{query: "select name from members", name: "", about: ""}
    finish = ReportJob.build(team, report, "add standing", @now).finish

    assert {:ok,
            %{query: "select name, standing from members", name: "Standing", note: "Added it."}} =
             finish.(%{
               "query" => "select name, standing from members",
               "name" => "Standing",
               "note" => "Added it."
             })

    assert {:retry, mistake} =
             finish.(%{"query" => "select nme from members", "name" => "", "note" => ""})

    assert mistake =~ "Did you mean name?"

    assert {:unchanged, "No field has shoe sizes."} =
             finish.(%{"query" => "", "name" => "", "note" => "No field has shoe sizes."})
  end

  test "a report that has a name keeps it" do
    team = team_fixture()
    report = %{query: "select name from members", name: "Everyone", about: ""}
    finish = ReportJob.build(team, report, "add standing", @now).finish

    assert {:ok, %{name: nil}} =
             finish.(%{
               "query" => "select name, standing from members",
               "name" => "New",
               "note" => ""
             })
  end

  defp prompt(job), do: %{"role" => "user", "content" => job.prompt}
end
