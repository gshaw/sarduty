defmodule App.DocumentTest do
  use ExUnit.Case, async: true

  # cspell:ignore totl incidnt -- misspelled on purpose

  alias App.Document
  alias App.Document.Checker
  alias App.Model.Member
  alias App.Model.Team
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Parser
  alias App.Report.Query
  alias App.Report.Result

  @now ~U[2026-01-15 18:00:00Z]
  @team %Team{
    id: 1,
    name: "Coast Range SAR",
    legal_name: "Coast Range Search and Rescue Society",
    mailing_address: "123 Main St",
    timezone: "America/Vancouver",
    authorized_by_name: "Alex Chen"
  }

  # A team admin's catalog, read from nothing.
  defp context do
    %Context{
      team: @team,
      now: @now,
      dates_now: @now,
      timezone: @team.timezone,
      today: ~D[2026-01-15],
      dates_today: ~D[2026-01-15],
      hours_tags: %{},
      years: [],
      tags: [],
      groups: []
    }
  end

  defp letter do
    {:ok, doc} = "tax_credit_letter" |> Document.read() |> Document.parse()
    {:ok, doc} = Document.check(doc, context())
    doc
  end

  defp checked(text) do
    with {:ok, doc} <- Document.parse(text), do: Document.check(doc, context())
  end

  defp error(text) do
    {:error, error} = checked(text)
    Error.text(error)
  end

  @places """
  places
    body flow down, top 1in, left 1in, right 1in
  """

  # The smallest document, with `fill` under `places`.
  defp doc(head, fill),
    do: "document 'Test'\nfor member, year\n#{head}\n#{@places}fill\n  body =\n    #{fill}\n"

  # The smallest form, with `head` after for, and its places and fill.
  defp form(head, places \\ ["body text top 1in, left 1in, width 2in"], fill \\ ["body = 'x'"]),
    do:
      "form 'Test'\nfor activity where kind = 'incident'\n#{head}\npage\nplaces\n" <>
        Enum.map_join(places, &"  #{&1}\n") <> "fill\n" <> Enum.map_join(fill, &"  #{&1}\n")

  # Coast Range SAR's catalog, with its custom fields (#816).
  defp sample_context, do: Context.new(App.SampleRepo.team(), @now, repo: App.SampleRepo)

  defp task_report do
    {:ok, doc} = "test/support/fixtures/forms/task_report.txt" |> File.read!() |> Document.parse()
    {:ok, doc} = Document.check(doc, sample_context())
    doc
  end

  defp claim do
    {:ok, doc} = "test/support/fixtures/forms/claim_rules.txt" |> File.read!() |> Document.parse()
    {:ok, doc} = Document.check(doc, sample_context())
    doc
  end

  # What a small form works out, from the consts, asks, and computes in `head`.
  defp worked(head, values \\ %{}, timezone \\ "America/Vancouver") do
    {:ok, doc} = checked(form(head))
    Document.values(doc, values, timezone)
  end

  defp money(values, name), do: Service.Format.money(values[name])

  test "every document parses, checks against the catalog, and its expects hold" do
    names = Document.names()
    assert "tax_credit_letter" in names

    for name <- names do
      assert {:ok, doc} = name |> Document.read() |> Document.parse(), name
      assert {:ok, doc} = Document.check(doc, context()), name
      assert doc.expects != [], "#{name} has no expect"
      assert Document.expect(doc) == :ok, name
    end
  end

  describe "the tax credit letter" do
    test "titles the PDF, locks it, and keeps the hours" do
      values = %{
        ":year" => 2025,
        "team.legal_name" => @team.legal_name,
        "hours.primary" => 210,
        "hours.secondary" => 60
      }

      output = Document.evaluate(letter(), values, @team.timezone)

      assert output.title == "2025 SRVTC Coast Range Search and Rescue Society"
      assert output.author == "Coast Range Search and Rescue Society"
      assert output.lock == :print
      assert output.keep == %{"hours.primary" => 210, "hours.secondary" => 60}
    end

    test "prints the logos in a row, the signature, and the verify link's QR code" do
      values = %{
        "team.logo" => "team png",
        "team.signature" => "signature png",
        "pdf.verify_link" => "https://verify.sarduty.com/letters/SRVTC-7KQ2M9XD"
      }

      places = Map.new(Document.evaluate(letter(), values, "Etc/UTC").places, &{&1.name, &1})

      # No organization logo: the team's alone, in the top right corner.
      assert %{across: true, top: 72, right: 72, height: 72, gap: 18.0} = places["letterhead"]
      assert places["letterhead"].value == [{:image, "team png", %{}}]

      assert %{level_with: "letter", right: 72, width: 72} = places["verify"]
      assert places["verify"].value == {:qr, "https://verify.sarduty.com/letters/SRVTC-7KQ2M9XD"}

      # The signature takes the place of the blank lines.
      items = places["letter"].value
      assert {:image, "signature png", %{width: 216, height: 54.0, pad: 6}} in items

      refute Enum.any?(items, &match?({:space, 4}, &1))
      assert %{size: 12, leading: 14.4, top: 72, left: 72, right: 72} = places["letter"]
    end

    test "has no picture without a logo, a signature, or a link" do
      places = Map.new(Document.evaluate(letter(), %{}, "Etc/UTC").places, &{&1.name, &1})

      assert places["letterhead"].value == []
      assert places["verify"].value == nil
      assert {:space, 4} in places["letter"].value
    end

    test "reads its reports, the team's fields, and nothing only printing reads" do
      queries = letter() |> Document.queries() |> Map.new()
      assert Map.keys(queries) == ["hours", "member", "team"]
      assert queries["hours"].from == "tax_credit_hours"

      team_fields = Enum.map(queries["team"].select, &Query.text/1)
      assert "legal_name" in team_fields
      refute "signature" in team_fields
      refute "logo" in team_fields
    end
  end

  test "a report's row reads as report.column, and a record as its name" do
    {:ok, query} = Parser.parse("select name, address from members")

    result = %Result{
      columns: [%{type: {:record, :member}}, %{type: :text}],
      rows: [[7, "1 Elm St"], [8, "2 Oak St"]]
    }

    records = %{member: %{7 => %Member{id: 7, name: "Avery Chen"}}}

    assert Document.put_row(%{}, "member", query, result, records) == %{
             "member.name" => "Avery Chen",
             "member.address" => "1 Elm St"
           }

    assert Document.put_row(%{"a" => 1}, "member", query, %Result{rows: []}) == %{"a" => 1}
  end

  describe "values" do
    defp text_of(fill, values) do
      {:ok, doc} = checked(doc("", fill))
      doc |> Document.evaluate(values, "America/Toronto") |> Document.text("body")
    end

    test "put values in text, format them, and leave blank items out" do
      values = %{"team.legal_name" => "Coast Range", "team.signer" => nil, ":year" => 2025}

      assert text_of("'{team.legal_name} in {:year}'", values) == "Coast Range in 2025"
      assert text_of("team.signer", values) == ""
      assert text_of("coalesce(team.signer, team.legal_name)", values) == "Coast Range"
      assert text_of("'Signer: {team.signer}' if team.signer is not null", values) == ""

      assert text_of("if team.signer is null then 'none' else 'some'", values) == "none"
      assert text_of("if team.signer = 'x' or :year > 2024 then 'yes' else 'no'", values) == "yes"
    end

    test "format dates in the team's zone" do
      assert text_of("today as date_long", %{"today" => ~D[2026-03-08]}) == "March 8, 2026"
    end

    test "a flow's spaces are blank lines, and a value's lines are lines" do
      values = %{"team.mailing_address" => "Box 1\nHope BC"}

      assert text_of("team.mailing_address\n    space 2\n    'End'", values) ==
               "Box 1\nHope BC\n\n\nEnd"
    end
  end

  describe "a form" do
    test "the sample form checks against Coast Range SAR's catalog, and its expects hold" do
      doc = task_report()

      assert doc.kind == :form
      assert doc.for == ["activity"]
      assert doc.page
      assert Document.expect(doc) == :ok
      assert Enum.map(doc.asks, & &1.name) == ~w(leader injured notes err)
      assert %{remember: true, hint: "They sign the report by hand."} = hd(doc.asks)
      assert doc.types[":injured"] == :number
      assert doc.types[":err"] == :text
    end

    test "shows on the activities its where says" do
      assert Query.text(Document.shown_on(task_report()).where) ==
               "id = :activity and kind = 'incident'"

      {:ok, doc} = "" |> form() |> String.replace(" where kind = 'incident'", "") |> checked()
      assert Query.text(Document.shown_on(doc).where) == "id = :activity"
    end

    test "an answer not given takes its default, which can read an answer above it" do
      head = "ask meals 'Meals for everyone' default 0\nask given 'Meals given' default :meals"

      {:ok, doc} =
        checked(form(head, ["body text top 1in, left 1in"], ["body = :given as number"]))

      assert doc |> Document.evaluate(%{}, "Etc/UTC") |> Document.text("body") == "0"

      assert doc |> Document.evaluate(%{":meals" => 2}, "Etc/UTC") |> Document.text("body") ==
               "2"

      values = %{":meals" => 2, ":given" => 1}
      assert doc |> Document.evaluate(values, "Etc/UTC") |> Document.text("body") == "1"
    end

    test "a tick holds or doesn't, and each place keeps its page" do
      output = Document.evaluate(task_report(), %{":err" => "Yes"}, "Etc/UTC")
      places = Map.new(output.places, &{&1.name, &1})

      assert output.page
      assert %{kind: :tick, value: true, page: 2, size: 9} = places["err"]
      assert %{value: false, page: 1} = places["search"]
      assert %{fit: true, width: 132} = places["task_number"]
      assert %{fit: false, pitch: 18} = places["description"]
      assert %{right: 72, page: 2} = places["prepared"]
    end

    test "keeps its answers" do
      output = Document.evaluate(task_report(), %{":leader" => "Jordan Lee"}, "Etc/UTC")
      assert output.keep == %{":leader" => "Jordan Lee", ":injured" => 0, ":err" => "No"}
    end

    test "reads what a person typed by each answer's type" do
      doc = task_report()

      assert Document.answers(doc, %{"injured" => " 2 ", "err" => "Yes", "notes" => ""}) ==
               {:ok, %{":injured" => 2, ":err" => "Yes"}}

      assert Document.answers(doc, %{"injured" => "1.5"}) == {:ok, %{":injured" => 1.5}}

      assert Document.answers(doc, %{"injured" => "two", "err" => "yes"}) ==
               {:error, %{"injured" => "Enter a number, such as 3.", "err" => "Pick Yes or No."}}

      {:ok, doc} = checked(form("ask on 'Date report completed' default today"))
      assert doc.types[":on"] == :day
      assert Document.answers(doc, %{"on" => "2026-11-06"}) == {:ok, %{":on" => ~D[2026-11-06]}}

      assert Document.answers(doc, %{"on" => "Nov 6"}) ==
               {:error, %{"on" => "Enter a date, such as 2026-11-06."}}
    end
  end

  describe "arithmetic" do
    test "the claim's rules check on Coast Range SAR, and their expects hold" do
      doc = claim()

      assert Document.expect(doc) == :ok
      assert Enum.map(doc.consts, & &1.name) == ~w(km_rate meal meals_a_day equipment_rate ohs)

      assert [%{value: 0.65, from: nil}, %{value: 0.67, from: ~D[2026-04-15]}] =
               hd(doc.consts).values

      assert List.last(doc.consts).values == [%{value: 0.15, from: nil}]
      assert for(%{each: "people", name: name} <- doc.asks, do: name) == ~w(on_task meals_given)
      assert for(%{rows: true, name: name} <- doc.reports, do: name) == ~w(people equipment)
      assert doc.types |> Checker.row_types("people") |> Map.fetch!("meals_given") == :number
    end

    test "works out each person's claim, and the totals, in exact decimals" do
      values = %{
        "task.`Response Type`" => "Response",
        "people" => [
          %{
            key: "member:7",
            values: %{
              "member" => "Avery Chen",
              "started_at" => ~U[2026-06-01 15:00:00Z],
              "finished_at" => ~U[2026-06-01 21:30:00Z],
              "km" => 30
            }
          },
          # Starts on Apr 14 in Vancouver, before the new rate, and runs 26 hours.
          %{
            key: "member:8",
            values: %{
              "member" => "Jordan Lee",
              "started_at" => ~U[2026-04-15 06:00:00Z],
              "finished_at" => ~U[2026-04-16 08:00:00Z],
              "km" => 12
            }
          }
        ],
        {"meals_given", "member:8"} => 1,
        ":misc" => 40
      }

      values = Document.values(claim(), values, "America/Vancouver")
      [avery, jordan] = Enum.map(values["people"], & &1.values)

      # 30 km at $0.67, 2 meals, and a day's equipment.
      assert avery["rate"] == 0.67
      assert Decimal.eq?(avery["hours"], "6.5")
      assert {money(avery, "meals"), money(avery, "allowance")} == {"$2.00", "$25.00"}
      assert money(avery, "total") == "$75.10"

      # 12 km at $0.65, 8 meals less the 1 given, and 2 days' equipment.
      assert jordan["rate"] == 0.65
      assert jordan["meals_given"] == 1
      assert money(jordan, "total") == "$162.80"

      assert money(values, "personnel") == "$237.90"
      assert money(values, "subtotal") == "$277.90"
      # 15% of $277.90 is $41.685, which rounds up.
      assert money(values, "ohs_total") == "$41.69"
      assert money(values, "total") == "$319.59"
      assert Decimal.to_string(values["total"]) == "319.59"
    end

    test "a blank counts as 0, dividing by 0 is blank, and decimals are exact" do
      values =
        worked("""
        report task
          select attended_count from activities where id = :activity
        ask a 'A' default 0
        compute
          x = :a + 1
          y = 1 / :a
          z = task.attended_count * 2
          w = 0.1 + 0.2
        """)

      assert Decimal.eq?(values["x"], 1)
      assert values["y"] == nil
      assert Decimal.eq?(values["z"], 0)
      assert Decimal.to_string(values["w"]) == "0.3"
    end

    test "functions: days, floor, round, min, max, and hours" do
      values =
        worked(
          """
          report task
            select started_at, finished_at, attended_hours from activities where id = :activity
          compute
            a = days(6)
            b = days(25)
            c = days(0)
            d = floor(7 / 3)
            e = round(2.5)
            f = round(11.265, 2)
            g = min(3, 1, 2)
            h = max(0, 2 - 5)
            i = hours(task.started_at, task.finished_at)
            j = hours(task.attended_hours)
            k = hours(2026-06-01, 2026-06-02)
          """,
          %{
            "task.started_at" => ~U[2026-06-01 15:00:00Z],
            "task.finished_at" => ~U[2026-06-01 19:45:00Z],
            "task.attended_hours" => 870
          }
        )

      texts = Map.new(~w(a b c d e f g h i j k), &{&1, Decimal.to_string(values[&1], :normal)})

      assert texts == %{
               "a" => "1",
               "b" => "2",
               "c" => "0",
               "d" => "2",
               "e" => "3",
               "f" => "11.27",
               "g" => "1",
               "h" => "0",
               "i" => "4.75",
               "j" => "14.5",
               "k" => "24"
             }
    end

    test "a const reads on a day: the last value that starts by then" do
      head = """
      report task
        select started_at from activities where id = :activity
      const rate = 0.65, 0.67 from 2026-04-15, 0.70 from 2027-01-01
      ask day 'Day' default today
      compute
        on_day = rate on :day
        started = rate on task.started_at
      """

      for {day, rate} <- [
            {~D[2026-04-14], 0.65},
            {~D[2026-04-15], 0.67},
            {~D[2027-03-01], 0.7}
          ],
          do: assert(worked(head, %{":day" => day})["on_day"] == rate)

      # 06:00 UTC is still Apr 14 in Vancouver.
      started = %{"task.started_at" => ~U[2026-04-15 06:00:00Z]}
      assert worked(head, started)["started"] == 0.65
      assert worked(head, started, "Etc/UTC")["started"] == 0.67
      assert worked(head)["started"] == nil
    end

    test "an answer on each row is typed for the row's member, and read in its row" do
      doc = claim()

      typed = %{
        "on_task" => %{"member:7" => "No"},
        "meals_given" => %{"member:7" => "2", "member:8" => "a few"},
        "misc" => "12.50"
      }

      assert Document.answers(doc, typed) ==
               {:error, %{"meals_given" => %{"member:8" => "Enter a number, such as 3."}}}

      typed = put_in(typed["meals_given"]["member:8"], " ")

      assert {:ok, answers} = Document.answers(doc, typed)

      assert answers == %{
               {"on_task", "member:7"} => "No",
               {"meals_given", "member:7"} => 2,
               ":misc" => 12.5
             }

      row = %{key: "member:7", values: %{"started_at" => ~U[2026-06-01 15:00:00Z], "km" => 10}}
      values = Map.put(answers, "people", [row])
      [row] = Document.values(doc, values, "America/Vancouver")["people"]

      # Off task, a person claims only their km.
      assert row.values["on_task"] == "No"
      assert Decimal.eq?(row.values["meals"], 0)
      assert Service.Format.money(row.values["total"]) == "$6.70"
    end

    test "a report with a row each keeps every row, by its member or item" do
      {:ok, query} = Parser.parse("select member, km from attendance")

      result = %Result{
        columns: [%{type: {:record, :member}}, %{type: :km}],
        rows: [[7, 30], [8, nil]]
      }

      records = %{member: %{7 => %Member{id: 7, name: "Avery Chen"}}}

      assert Document.put_rows(%{}, "people", query, result, records) == %{
               "people" => [
                 %{key: "member:7", values: %{"member" => "Avery Chen", "km" => 30}},
                 %{key: "member:8", values: %{"member" => nil, "km" => nil}}
               ]
             }
    end
  end

  describe "mistakes" do
    test "name the line and say how to fix it" do
      assert error("for member") =~ "Start with document"

      assert error("document 'A'\nplaces\n  a text top 1in, left 1in\nfor member") ==
               "Line 4: Move for before places."

      assert error("document 'A'\nfrom x") =~ "Line 2: Start a clause here"
      assert error("document 'A'\nfor member") == "Add places: where each value goes on the page."

      assert error("document 'A'\nfor team") ==
               "Line 2: A document starts from member or year, not team."
    end

    test "check every name against the catalog" do
      assert error(doc("", "team.legal_nme")) ==
               "Line 8: team has no field legal_nme. Did you mean legal_name?"

      assert error(doc("", "hours.total")) =~ "Line 8: There is no hours.total."

      assert error(doc("report hours\n  select totl from tax_credit_hours", "'x'")) =~
               "Line 4:"

      assert error(
               doc("report hours\n  select total from tax_credit_hours where year = :when", "'x'")
             ) ==
               "Line 4: Add when after for, or take :when out."

      assert error(doc("report hours\n  select sum(total) from tax_credit_hours", "'x'")) ==
               "Line 4: Select fields in a document's report, not sum(total)."
    end

    test "check each value's type" do
      assert error(doc("", "team.legal_name as duration")) =~ "Take out as duration"
      assert error(doc("", "team.logo")) =~ "Write image before it"
      assert error(doc("", "image team.legal_name")) =~ "Write an image after image"
      assert error(doc("", "qr(team.logo)")) =~ "Give qr a link"
      assert error(doc("", "'{today as km}'")) =~ "Show TODAY as date_long or date_short."
    end

    test "a form starts from an activity, and only a form does" do
      assert error("form 'A'\npage\nplaces\n  a text top 1in, left 1in\nfill\n  a = 'x'\n") =~
               "Write for activity after the form's name"

      assert error("form 'A'\nfor member") ==
               "Line 2: A form starts from an activity: for activity where kind = 'incident'."

      assert error("document 'A'\nfor activity") ==
               "Line 2: Start with form 'Its name': what starts from an activity is a form."

      assert error("document 'A'\nfor member where kind = 'incident'") ==
               "Line 2: Take out where: it says which activities show a form."

      assert "" |> form() |> String.replace("'incident'", "'incidnt'") |> error() =~ "Line 2:"

      assert "" |> form() |> String.replace("kind = 'incident'", "id = :activity") |> error() ==
               "Line 2: Take out :activity: where reads only the activity's fields."

      assert error(form("lock print")) == "Take out lock: an agency writes on a form's PDF."
    end

    test "check each ask" do
      assert error(form("ask injured")) =~ "Line 3: Write the answer's name and its label"
      assert error(form("ask a 'A' remember remember")) == "Line 3: Write remember once."
      assert error(form("ask a 'A' often")) =~ "Line 3: Remove often: an ask takes"

      assert error(form("ask a 'A'\nask a 'B'")) ==
               "Line 4: Give the ask another name: a is used twice."

      assert error(form("ask activity 'A'")) ==
               "Line 3: Give the ask another name: :activity is what the form starts from."

      assert error(form("ask a 'A' choose 'Yes'")) =~ "Line 3: Give choose two answers or more"

      assert error(form("ask a 'A' choose 'Yes', 'No' default 'Maybe'")) ==
               "Line 3: Make the default one of the choices: 'Yes' or 'No'."

      assert error(form("ask a 'A' default team.logo")) =~ "Line 3: Give default text, a number"

      assert error(form("ask a 'A' default :b\nask b 'B'")) =~
               "Line 3: Add b after for or ask for it"

      assert error(form("ask a 'A'\nkeep :activity")) =~
               "Line 4: Keep a report's value or an answer"
    end

    test "check a form's places" do
      assert error(form("", ["body tick top 1in, left 1in"], ["body = :activity > 0"])) ==
               "Line 6: Give body a size: the side of its box, such as size 9pt."

      assert error(form("", ["body tick top 1in, left 1in, size 9pt"], ["body = 'x'"])) =~
               "Line 8: Fill body with a condition"

      assert error(form("", ["body image top 1in, left 1in, fit"], ["body = team.logo"])) ==
               "Line 6: Take out fit: only a text place shrinks to fit."

      assert error(form("", ["body text top 1in, left 1in, fit"])) ==
               "Line 6: Give body a width, or left and right: fit shrinks the text to it."

      assert error(form("", ["body text top 1in, left 1in, width 1in, fit, pitch 12pt"])) ==
               "Line 6: Write fit or pitch, not both: fit keeps the text on one line."

      assert error(form("", ["body text top 1in, left 1in, width 1in, fit, indent 1in"])) ==
               "Line 6: Write fit or indent, not both: fit keeps the text on one line."

      assert error(form("", ["body text top 1in, left 1in, width 1in, lines 8"])) ==
               "Line 6: Give body a pitch with lines: lines counts the page's lines."

      assert error(form("", ["body text top 1in, left 1in, pitch 12pt, lines 0"])) ==
               "Line 6: Write how many lines after lines, such as lines 8."

      assert error(
               form("", ["body tick top 1in, left 1in, size 9pt, indent 1in"], ["body = 1 = 1"])
             ) ==
               "Line 6: Take out indent: only a text place starts further in."

      assert error(form("", ["body text top 1in, left 1in, page 0"])) ==
               "Line 6: Write which page after page, such as page 2."

      assert error(doc("", "'x'") |> String.replace("right 1in", "right 1in, page 2")) ==
               "Line 5: Take out page 2, or add page: only a form's page has pages."

      flow = "body flow down, top 1in, left 1in"
      qr = "code image right 1in, width 1in, height 1in, level with body, page 2"

      assert error(form("", [flow, qr], ["body = 'x'", "code = qr('x')"])) ==
               "Line 7: Put code on page 1, where body is."

      assert error("form 'A'\nfor activity\npage x") ==
               "Line 3: Write page alone: the values print on the form's own page."
    end

    test "check consts and computes" do
      assert error(form("const rate = 0.67 from 2026-04-15")) ==
               "Line 3: Start with the value before any day, such as 0.65, 0.67 from 2026-04-15."

      assert error(form("const rate = 1, 2 from 2026-05-01, 3 from 2026-04-01")) ==
               "Line 3: Write the values in order of the day each starts, earliest first."

      assert error(form("const rate = 1, 2")) =~
               "Line 3: Write the day each later value starts"

      assert error(form("const rate = 1, 'a' from 2026-05-01")) ==
               "Line 3: Give rate values of one kind: all numbers, text, or dates."

      assert error(form("const today = 1")) ==
               "Line 3: Give the const another name: today is used above."

      assert error(form("const rate = 0.65, 0.67 from 2026-04-15\ncompute\n  x = rate * 2")) ==
               "Line 5: Read rate on a day, such as rate on started_at: it changes on 2026-04-15."

      assert error(form("compute\n  x = rate on today")) ==
               "Line 4: Read a const on a day, such as km_rate on started_at, not rate."

      assert error(form("const rate = 1\ncompute\n  x = rate on 3")) ==
               "Line 5: Write a day after on, such as rate on started_at."

      assert error(form("compute\n  x = 1\ncompute\n  x = 2")) ==
               "Line 6: Give the compute another name: x is used above."

      assert error(form("compute\n  x = y + 1\n  y = 2")) =~ "Line 4: There is no y."
      assert error(form("compute\n  x =")) == "Line 4: Write a value after =."
      assert error(form("compute x = 1")) =~ "Line 3: Write compute alone, or compute each"
    end

    test "check arithmetic and functions" do
      assert error(form("compute\n  x = 'a' + 1")) == "Line 4: Use a number here, not 'a'."

      duration =
        "report task\n  select attended_hours from activities where id = :activity\ncompute\n" <>
          "  x = task.attended_hours * 2"

      assert error(form(duration)) ==
               "Line 6: Read task.attended_hours in hours with hours(task.attended_hours): " <>
                 "a duration is kept in minutes."

      assert error(form("compute\n  x = floor(1, 2)")) ==
               "Line 4: Give floor one number, such as floor(hours / 3)."

      assert error(form("compute\n  x = round(1, 'a')")) ==
               "Line 4: Give round a number and how many decimals, such as round(total, 2)."

      assert error(form("compute\n  x = min(1)")) ==
               "Line 4: Give min two numbers or more, such as min(0, total)."

      assert error(form("compute\n  x = hours(today)")) =~ "Line 4: Give hours a duration"

      assert error(form("compute\n  x = count(1)")) ==
               "Line 4: There is no function count. Use coalesce, qr, hours, days, floor, round, min, max, sum."

      assert error(form("compute\n  x = -today")) =~ "Line 4: Write a number after -"
    end

    test "check each report's rows" do
      people =
        "report people\n  select member, km from attendance where activity.id = :activity\n"

      assert error(form("compute each people\n  x = 1")) ==
               "Line 4: There is no report people. Write report people and its query above."

      assert error(form(people <> "compute each people\n  km = 1")) ==
               "Line 6: Give the compute another name: km is one of people's values."

      assert error(form(people <> "compute each people\n  x = km\ncompute\n  y = people.x")) ==
               "Line 8: Add up people.x with sum(people.x): people has a row each."

      assert error(form(people <> "compute\n  y = sum(km)")) ==
               "Line 6: Give sum one column of a report with a row each, such as sum(people.total)."

      assert error(
               form(people <> "compute each people\n  x = km\ncompute\n  y = sum(people.kms)")
             ) ==
               "Line 8: people has no kms. Did you mean km?"

      assert error(form(people <> "ask each people a 'A' remember")) ==
               "Line 5: Take out remember: an answer for each row starts from its default."

      assert error(form(people <> "ask each people km 'Km'")) ==
               "Line 5: Give the ask another name: km is one of people's values."

      no_member = "report people\n  select km from attendance where activity.id = :activity\n"

      assert error(form(no_member <> "ask each people a 'A'")) ==
               "Line 5: Select member or item in report people: each row's answer is kept by it."

      rows = form(people <> "compute each people\n  y = 1")

      assert error(rows <> "expect with people kms 30: y = 1\n") ==
               "Line 12: people has no kms. Did you mean km?"

      assert error(rows <> "expect with task hours 3: y = 1\n") =~
               "Line 12: There is no report task with a row each."
    end

    test "never keep what only printing reads" do
      assert error(doc("keep team.signature", "'x'")) ==
               "Line 3: Keep a value a report reads: team.signature only prints."
    end

    test "fill every place, once" do
      text =
        "document 'A'\nplaces\n  a text top 1in, left 1in\n  b text top 2in, left 1in\nfill\n  a = 'x'\n"

      assert error(text) == "Line 4: Fill b: write what goes in it under fill."

      assert error("document 'A'\nplaces\n  a text top 1in\nfill\n  a = 'x'\n") ==
               "Line 3: Say where a sits across the page: left or right."
    end

    test "an expect that fails names its line and what the place holds" do
      text = doc("", "'In {:year}'") <> "expect with :year = 2025: body contains '2024'\n"
      {:ok, doc} = checked(text)
      assert {:error, [%Error{line: 9, message: message}]} = Document.expect(doc)
      assert message =~ "body contains '2024'."
      assert message =~ ~s(body is "In 2025")
    end
  end
end
