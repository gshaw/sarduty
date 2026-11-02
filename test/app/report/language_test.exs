defmodule App.Report.LanguageTest do
  # How to write a report (#803) is built from the code, so it can't drift from it.
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Report
  alias App.Report.Catalog
  alias App.Report.Language
  alias App.Report.Parser

  test "every clause has an entry" do
    names = Enum.map(Language.clause_entries(), &elem(&1, 0))
    assert names -- ~w(option each) == Parser.clauses() ++ Parser.page_clauses()
  end

  test "every function and date range has an entry" do
    assert Enum.sort(Parser.functions()) ==
             Language.function_entries() |> Map.keys() |> Enum.sort()

    assert Enum.sort(Parser.ranges()) == Language.range_entries() |> Map.keys() |> Enum.sort()
  end

  test "every subject has a sentence" do
    assert Enum.sort(Catalog.names()) == Language.subject_entries() |> Map.keys() |> Enum.sort()
  end

  test "every field argument has an entry" do
    kinds =
      for subject <- Catalog.subjects(),
          field <- subject.fields,
          arg <- field.args,
          uniq: true,
          do: arg

    assert Enum.sort(kinds) == Language.arg_entries() |> Map.keys() |> Enum.sort()
  end

  test "every example checks" do
    team = team_fixture()

    for text <- Language.examples() do
      assert {:ok, _plan} = Report.check(text, team, %{"year" => "2026"}), text
    end
  end

  test "every subject and field is on the page" do
    text = Language.markdown()

    for subject <- Catalog.subjects() do
      assert text =~ "### #{subject.name}\n"

      for field <- subject.fields,
          not field.hidden,
          do: assert(text =~ "| `#{Language.field_text(field)}` |")
    end
  end

  test "it says who can read a field, and which choices are everyone's" do
    text = Language.markdown()

    assert text =~ "| `not_seen(days)` | true or false |"
    assert text =~ "Only team admins can read it."
    assert text =~ "Only teams with custom fields have it."
    assert text =~ "Only team admins see Away."
    assert text =~ "Kind. One of Incident, Exercise, Event."
  end
end
