defmodule App.Operation.SaveFormAnswersTest do
  # Checks the test form on Coast Range SAR's own database (#816). No sandbox: it only
  # reads, as every sample run does.
  use ExUnit.Case, async: true

  alias App.Document
  alias App.Operation.SaveFormAnswers
  alias App.Report.Context
  alias App.SampleRepo

  @form File.read!("test/support/fixtures/forms/task_report.txt")

  setup_all do
    context = Context.new(SampleRepo.team(), DateTime.utc_now(), repo: SampleRepo)
    {:ok, doc} = Document.parse(@form)
    {:ok, doc} = Document.check(doc, context)
    %{doc: doc}
  end

  test "saves a new or changed answer, and nothing for one the same", %{doc: doc} do
    saved = %{"leader" => "Alex Chen", "injured" => "0"}
    typed = %{"leader" => "Alex Chen", "injured" => " 2 ", "err" => "Yes"}

    assert SaveFormAnswers.plan(doc, saved, typed) ==
             %{put: %{"injured" => "2", "err" => "Yes"}, delete: [], errors: %{}}
  end

  test "a blank answer deletes the saved one, so the default holds", %{doc: doc} do
    plan = SaveFormAnswers.plan(doc, %{"injured" => "2"}, %{"injured" => "", "notes" => ""})
    assert plan == %{put: %{}, delete: ["injured"], errors: %{}}
  end

  test "only the form's asks count", %{doc: doc} do
    assert SaveFormAnswers.plan(doc, %{}, %{"misc" => "40"}) ==
             %{put: %{}, delete: [], errors: %{}}
  end

  test "saves those that read, and says what's wrong with the rest", %{doc: doc} do
    typed = %{"leader" => "Alex Chen", "injured" => "a few", "err" => "Maybe"}

    assert SaveFormAnswers.plan(doc, %{}, typed) == %{
             put: %{"leader" => "Alex Chen"},
             delete: [],
             errors: %{"injured" => "Enter a number, such as 3.", "err" => "Pick Yes or No."}
           }
  end
end
