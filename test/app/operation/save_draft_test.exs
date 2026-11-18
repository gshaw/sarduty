defmodule App.Operation.SaveDraftTest do
  # Saved AI turns (#1089): what a draft keeps, and how a conversation goes into a row
  # and comes back as the page keeps it.
  use ExUnit.Case, async: true

  alias App.Model.AIDraft
  alias App.Model.Form
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Operation.SaveDraft

  @team %Team{id: 1}
  @report %SavedReport{id: 2, name: "Members", about: nil, query: "select name from members"}
  @form %Form{id: 3, text: "form 'Task report'", page_sha256: Form.sha256("saved page")}

  describe "keep?/3" do
    test "a saved report: a change, or a conversation" do
      same = %{"name" => "Members", "about" => "", "query" => "select name from members"}
      refute SaveDraft.keep?({@team, @report}, Map.put(same, "values", %{"year" => "2026"}), [])
      assert SaveDraft.keep?({@team, @report}, %{same | "name" => "Everyone"}, [])
      assert SaveDraft.keep?({@team, @report}, same, [%{ask: "Who came?", note: "Avery."}])
    end

    test "a new report, once AI has answered an ask" do
      fields = %{"name" => "", "about" => "", "query" => "select name from members"}
      refute SaveDraft.keep?({@team, nil}, %{fields | "name" => "Mine"}, [])
      refute SaveDraft.keep?({@team, nil}, fields, [%{ask: "x", failed: %{title: "Busy"}}])
      assert SaveDraft.keep?({@team, nil}, fields, [%{ask: "x", note: "Done.", failed: nil}])
    end

    test "a form: its text, its PDF, or a conversation" do
      same = %{"text" => @form.text, "page" => "saved page"}
      refute SaveDraft.keep?(@form, same, [])
      assert SaveDraft.keep?(@form, %{same | "text" => "form 'Debrief'"}, [])
      assert SaveDraft.keep?(@form, %{same | "page" => "new page"}, [])
      assert SaveDraft.keep?(@form, same, [%{ask: "Write this form."}])
    end
  end

  test "a form's conversation goes into a row by each PDF's SHA-256 and comes back" do
    failed = %{title: "AI is busy right now.", detail: "Ask again.", again?: true}

    asks = [
      %{
        id: 9,
        ask: "Fit the form to the agency's new PDF.",
        before: "form 'Task report'",
        before_page: "saved page",
        note: "It fits.",
        undo?: true,
        blank: [%{label: "Signature", why: "Signed by hand."}],
        next: ["Add a total row"]
      },
      %{
        id: 8,
        ask: "Sign it",
        before: "",
        before_page: "saved page",
        page: "new page",
        test?: false,
        note: nil,
        undo?: false,
        blank: [],
        next: [],
        failed: failed
      }
    ]

    fields = %{"text" => "form 'Debrief'", "page" => "new page"}
    {row_fields, row_asks, pages} = SaveDraft.encode(fields, asks)

    assert row_fields["page"] == Form.sha256("new page")
    assert Enum.at(row_asks, 1).page == Form.sha256("new page")

    assert pages == %{
             Form.sha256("saved page") => "saved page",
             Form.sha256("new page") => "new page"
           }

    # As SQLite gives it back: JSON, with string keys.
    draft = %AIDraft{
      fields: json(row_fields),
      asks: json(row_asks),
      updated_at: ~U[2026-11-17 22:42:00.000000Z]
    }

    %{fields: back, asks: [first, second], at: at} = SaveDraft.decode(draft, pages)
    assert back == fields
    assert at == draft.updated_at
    assert Map.delete(first, :id) == asks |> hd() |> Map.delete(:id) |> Map.put(:failed, nil)
    assert second.failed == failed
    assert second.page == "new page"
    assert first.id != second.id
  end

  test "a PDF the store no longer has comes back as the form's saved one" do
    draft = %AIDraft{
      fields: %{"text" => "x", "page" => Form.sha256("gone")},
      asks: [%{"ask" => "Fit it", "before_page" => Form.sha256("gone")}],
      updated_at: ~U[2026-11-17 22:42:00.000000Z]
    }

    %{fields: fields, asks: [ask]} = SaveDraft.decode(draft, %{}, "saved page")
    assert fields["page"] == "saved page"
    assert ask.before_page == "saved page"
  end

  test "a report's conversation keeps each ask's fields as the form sends them" do
    before = %{"name" => "", "about" => "", "query" => "select name from members"}
    asks = [%{id: 1, ask: "Who came?", before: before, note: "Avery.", undo?: true, next: []}]
    {fields, row_asks, pages} = SaveDraft.encode(%{"query" => "select 1"}, asks)
    assert pages == %{}

    draft = %AIDraft{fields: json(fields), asks: json(row_asks), updated_at: DateTime.utc_now()}
    %{asks: [ask]} = SaveDraft.decode(draft, %{})
    assert ask.before == before
    assert ask.undo?
  end

  defp json(term), do: term |> Jason.encode!() |> Jason.decode!()
end
