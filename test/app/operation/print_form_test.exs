defmodule App.Operation.PrintFormTest do
  # Reads Coast Range SAR's own database (#816), as trying a form will. No sandbox: it
  # only reads, as every sample run does.
  use ExUnit.Case, async: true

  import Ecto.Query

  alias App.Model.Activity
  alias App.Operation.PrintDocument
  alias App.Operation.PrintForm
  alias App.Report.Context
  alias App.SampleRepo

  @form File.read!("test/support/fixtures/forms/task_report.txt")
  @page_source File.read!("test/support/fixtures/forms/task_report_page.typ")

  setup_all do
    {:ok, page} = Service.Typst.compile(@page_source)
    %{page: page}
  end

  defp context, do: Context.new(SampleRepo.team(), DateTime.utc_now(), repo: SampleRepo)

  defp activity(where) do
    team = SampleRepo.team()
    query = from(a in Activity, where: a.team_id == ^team.id, where: ^where, limit: 1)
    SampleRepo.one!(query)
  end

  defp incident, do: activity(dynamic([a], a.title == "Overdue kayakers"))

  test "prints an incident's form on every page of its own page, with the answers", %{page: page} do
    incident = incident()
    answers = %{"leader" => "Jordan Lee", "injured" => "1", "err" => "Yes"}

    assert {:ok, %{attachment: attachment, keep: keep}} =
             PrintForm.call(@form, page, context(), incident.id, answers)

    assert attachment.title == "Task report #{incident.ref_id}"
    assert attachment.filename == "Task_report_#{incident.ref_id}.pdf"
    assert attachment.content_type == "application/pdf"
    assert keep == %{":leader" => "Jordan Lee", ":injured" => 1, ":err" => "Yes"}

    # Letter, then legal, as the agency's page has them.
    sizes = Regex.scan(~r{/MediaBox\s*\[([^\]]*)\]}, attachment.content, capture: :all_but_first)
    assert sizes == [["0 0 612 792"], ["0 0 612 1008"]]
  end

  test "prints only on an activity its where shows it on", %{page: page} do
    training = activity(dynamic([a], a.activity_kind == "exercise"))

    assert PrintForm.call(@form, page, context(), training.id) ==
             {:error, "This form is not for this activity."}
  end

  test "checks each answer by its type, and names it", %{page: page} do
    answers = %{"injured" => "a few", "err" => "Maybe"}

    assert PrintForm.call(@form, page, context(), incident().id, answers) ==
             {:error, "Injured: Enter a number, such as 3. ERR attached: Pick Yes or No."}
  end

  test "says where a form's text is wrong", %{page: page} do
    text = String.replace(@form, "`People helped`", "`People halped`")
    assert {:error, message} = PrintForm.call(text, page, context(), incident().id)
    assert message =~ "Line 9:"

    text = String.replace(@form, "form 'Task report'", "document 'Task report'")
    assert {:error, message} = PrintForm.call(text, page, context(), incident().id)
    assert message =~ "a form"
  end

  describe "the page" do
    defp output(places),
      do: %{title: "Task report", author: nil, lock: nil, page: true, places: places}

    test "a form prints on its own page" do
      assert [] |> output() |> PrintDocument.call() ==
               {:error, "This form has no page to print on."}

      assert [] |> output() |> PrintDocument.call(page: "not a PDF") ==
               {:error, "SAR Duty cannot read this form's page. Upload it as a PDF."}
    end

    test "each place is on one of its pages", %{page: page} do
      tick = %{name: "err", kind: :tick, top: 110, left: 160, size: 9, value: true, page: 3}

      assert [tick] |> output() |> PrintDocument.call(page: page) ==
               {:error, "Place err is on page 3. The form's page has 2 pages."}
    end
  end
end
