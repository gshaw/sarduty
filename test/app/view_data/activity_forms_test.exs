defmodule App.ViewData.ActivityFormsTest do
  use ExUnit.Case, async: true

  alias App.Document
  alias App.Report.Context
  alias App.SampleRepo
  alias App.ViewData.ActivityForms

  @form File.read!("test/support/fixtures/forms/task_report.txt")

  test "each question starts from its answer, or a plain default" do
    {:ok, doc} = Document.parse(@form)

    assert ActivityForms.answers(doc, %{"leader" => "Alex Chen", "err" => "Yes"}) == %{
             "leader" => "Alex Chen",
             "injured" => "0",
             "notes" => nil,
             "err" => "Yes"
           }
  end

  test "blank is what a form prints as nothing" do
    for value <- [nil, "", []], do: assert(ActivityForms.blank?(value))
    for value <- [0, false, "0"], do: refute(ActivityForms.blank?(value))
  end

  # BCSARA's Expense reimbursement request asks nothing on each use, but works out each
  # one's total (#950).
  test "a report a form works out a value for on each row shows too, its total printed" do
    context = Context.new(SampleRepo.team(), DateTime.utc_now(), repo: SampleRepo)

    {:ok, doc} = "priv/forms/bcsara/expense_request.txt" |> File.read!() |> Document.parse()
    {:ok, doc} = Document.check(doc, context)

    use = fn hours ->
      %{
        key: "item:4",
        values: %{"item" => "Radio 1", "hours" => hours, "item.cost_per_hour" => 15}
      }
    end

    values = %{"people" => [], "equipment" => [use.(45), use.(240)]}

    assert [people, equipment] = ActivityForms.rows(doc, values, %{}, "America/Vancouver")
    assert {people.report, people.total} == {"people", "Total"}

    assert %{report: "equipment", kind: :item, asks: [], total: "Total"} = equipment

    # One item used twice: each row's element id is its own.
    assert Enum.map(equipment.rows, &{&1.dom, &1.name, &1.total}) == [
             {"equipment-1", "Radio 1", "$15.00"},
             {"equipment-2", "Radio 1", "$60.00"}
           ]
  end
end
