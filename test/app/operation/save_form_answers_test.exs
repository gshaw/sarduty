defmodule App.Operation.SaveFormAnswersTest do
  # Checks the test form on Coast Range SAR's own database (#816). No sandbox: it only
  # reads, as every sample run does.
  use ExUnit.Case, async: true

  alias App.Document
  alias App.Operation.SaveFormAnswers
  alias App.Report.Context
  alias App.SampleRepo

  @form File.read!("test/support/fixtures/forms/task_report.txt")
  @claim File.read!("priv/forms/bcsara/expense_request.txt")

  setup_all do
    context = Context.new(SampleRepo.team(), DateTime.utc_now(), repo: SampleRepo)

    [doc, claim] =
      for text <- [@form, @claim] do
        {:ok, doc} = Document.parse(text)
        {:ok, doc} = Document.check(doc, context)
        doc
      end

    %{doc: doc, claim: claim}
  end

  test "saves a new or changed answer, and nothing for one the same", %{doc: doc} do
    saved = %{"leader" => "Alex Chen", "injured" => "0"}
    typed = %{"leader" => "Alex Chen", "injured" => " 2 ", "err" => "Yes"}

    assert SaveFormAnswers.plan(doc, saved, typed) ==
             %{put: %{{"injured", ""} => "2", {"err", ""} => "Yes"}, delete: [], errors: %{}}
  end

  test "a blank answer deletes the saved one, so the default holds", %{doc: doc} do
    plan = SaveFormAnswers.plan(doc, %{"injured" => "2"}, %{"injured" => "", "notes" => ""})
    assert plan == %{put: %{}, delete: [{"injured", ""}], errors: %{}}
  end

  test "only the form's asks count", %{doc: doc} do
    assert SaveFormAnswers.plan(doc, %{}, %{"misc" => "40"}) ==
             %{put: %{}, delete: [], errors: %{}}
  end

  test "saves those that read, and says what's wrong with the rest", %{doc: doc} do
    typed = %{"leader" => "Alex Chen", "injured" => "a few", "err" => "Maybe"}

    assert SaveFormAnswers.plan(doc, %{}, typed) == %{
             put: %{{"leader", ""} => "Alex Chen"},
             delete: [],
             errors: %{"injured" => "Enter a number, such as 3.", "err" => "Pick Yes or No."}
           }
  end

  test "an answer on each row is kept by the row's member", %{claim: claim} do
    saved = %{"on_task" => %{"member:7" => "No", "member:8" => "No"}}
    typed = %{"on_task" => %{"member:7" => "No", "member:8" => "", "member:9" => "Maybe"}}

    assert SaveFormAnswers.plan(claim, saved, typed) == %{
             put: %{},
             delete: [{"on_task", "member:8"}],
             errors: %{"on_task" => %{"member:9" => "Pick Yes or No."}}
           }

    typed = %{"meals_given" => %{"member:7" => "2"}, "misc" => "40"}

    assert SaveFormAnswers.plan(claim, %{}, typed).put == %{
             {"meals_given", "member:7"} => "2",
             {"misc", ""} => "40"
           }
  end

  # A row's choice always sends one, so the form page's first change would keep every row.
  test "an answer on a row that's its plain default isn't kept", %{claim: claim} do
    saved = %{"on_task" => %{"member:8" => "No"}}
    typed = %{"on_task" => %{"member:7" => "Yes", "member:8" => "Yes", "member:9" => "No"}}

    assert SaveFormAnswers.plan(claim, saved, typed) == %{
             put: %{{"on_task", "member:9"} => "No"},
             delete: [{"on_task", "member:8"}],
             errors: %{}
           }

    # One that starts from another answer is kept as typed.
    typed = %{"meals_given" => %{"member:7" => "0"}}
    assert SaveFormAnswers.plan(claim, %{}, typed).put == %{{"meals_given", "member:7"} => "0"}
  end
end
