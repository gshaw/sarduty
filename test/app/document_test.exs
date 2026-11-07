defmodule App.DocumentTest do
  use ExUnit.Case, async: true

  # cspell:ignore Łukasz Dvořák totl

  alias App.Document
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.CreateTaxCreditLetter
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
    # The values the letter reads, as CreateTaxCreditLetter reads them.
    defp values(team, member, letter, now) do
      %{
        ":member" => member.id,
        ":year" => letter.year,
        "member.name" => member.name,
        "member.address" => member.address,
        "hours.primary" => letter.primary_minutes,
        "hours.secondary" => letter.secondary_minutes,
        "hours.total" => letter.primary_minutes + letter.secondary_minutes,
        "team.legal_name" => team.legal_name,
        "team.mailing_address" => team.mailing_address,
        "team.signer" => team.authorized_by_name,
        "team.signer_title" => team.authorized_by_title,
        "team.signer_phone" => team.authorized_by_phone,
        "team.signer_email" => team.authorized_by_email,
        "pdf.reference" => letter.ref_id,
        "today" => Service.Period.today(now, team.timezone)
      }
    end

    defp row(started_at, minutes, tags) do
      %{
        member_id: 7,
        started_at: started_at,
        finished_at: DateTime.add(started_at, minutes, :minute),
        duration_in_minutes: 0,
        tags: tags,
        chore: false
      }
    end

    test "says what CreateTaxCreditLetter's letter says, line for line" do
      member = %Member{id: 7, name: "Łukasz Dvořák", address: "1 Elm St, Hope BC"}

      rows = [
        row(~U[2025-03-01 17:00:00Z], 210, ["Primary Hours"]),
        row(~U[2025-04-01 17:00:00Z], 60, ["Secondary Hours"])
      ]

      teams = [
        @team,
        %{@team | authorized_by_name: nil},
        %{@team | authorized_by_phone: "604-555-0100", authorized_by_title: "President"},
        %{@team | authorized_by_email: "president@example.com", mailing_address: "Box 1\nHope BC"}
      ]

      members = [member, %{member | address: nil}, %{member | address: ""}]
      doc = letter()

      for team <- teams, member <- members, rows <- [rows, []] do
        planned = CreateTaxCreditLetter.plan(team, member, rows, 2025, "SRVTC-7KQ2M9XD", @now)
        output = Document.evaluate(doc, values(team, member, planned, @now), team.timezone)

        assert Document.text(output, "letter") ==
                 String.trim_trailing(planned.letter_content, "\n")
      end
    end

    test "titles the PDF, locks it, and keeps the hours" do
      member = %Member{id: 7, name: "Avery Chen"}
      planned = CreateTaxCreditLetter.plan(@team, member, [], 2025, "SRVTC-7KQ2M9XD", @now)
      output = Document.evaluate(letter(), values(@team, member, planned, @now), @team.timezone)

      assert output.title == "2025 SRVTC Coast Range Search and Rescue Society"
      assert output.author == "Coast Range Search and Rescue Society"
      assert output.lock == :print
      assert output.keep == %{"hours.primary" => 0, "hours.secondary" => 0}
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
