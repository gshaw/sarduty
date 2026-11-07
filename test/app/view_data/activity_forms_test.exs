defmodule App.ViewData.ActivityFormsTest do
  use ExUnit.Case, async: true

  alias App.Document
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
end
