defmodule App.FormsTest do
  # Each organization's form in priv/forms, as a SAR Duty admin uploads it (#950): its
  # text and its page save, which checks them on Coast Range SAR and runs every expect,
  # and it prints there. Coast Range SAR's own database only reads.
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Document
  alias App.Operation.PrintDocument
  alias App.Operation.SaveForm
  alias App.Operation.TryForm
  alias App.Report.Context
  alias App.Report.Query
  alias App.SampleRepo

  @dir "priv/forms"

  defp forms do
    for org <- File.ls!(@dir),
        name <- @dir |> Path.join(org) |> File.ls!(),
        Path.extname(name) == ".txt",
        do: Path.join([@dir, org, Path.rootname(name)])
  end

  test "every form saves, as it would upload, and prints on Coast Range SAR" do
    assert forms() != []
    admin = user_fixture(%{is_admin: true})

    for path <- forms() do
      text = File.read!(path <> ".txt")
      page = File.read!(path <> ".pdf")

      assert {:ok, form} = SaveForm.call(organization_fixture(), nil, text, page, admin),
             "#{path}: #{inspect(SaveForm.call(organization_fixture(), nil, text, page, admin))}"

      activity = form |> TryForm.activities() |> TryForm.first()
      assert {:ok, %{content: "%PDF" <> _rest}} = TryForm.call(form, activity.id), path
    end
  end

  describe "BCSARA's Task report" do
    setup do
      {:ok, doc} = "#{@dir}/bcsara/task_report.txt" |> File.read!() |> Document.parse()
      %{doc: doc}
    end

    test "is EMCR's 1.01 for an incident, and asks only what BCSARA's fields don't say",
         %{doc: doc} do
      assert doc.name == "Task report"

      assert Enum.map(doc.asks, & &1.name) ==
               ~w(others others_hours injured fatalities still_missing err)

      [task] = doc.reports
      fields = Enum.map(task.query.select, &Query.text/1)

      for field <- [
            "`Agency File #`",
            "`Region`",
            "`Area`",
            "`Task Type`",
            "`How many people received assistance from SAR?`",
            "`Equipment Used/Lost`",
            "`Task Leader's Name`",
            "`Date Report Completed`"
          ],
          do: assert(field in fields, field)
    end

    # find_places.py measured them on EMCR's page: each on its printed line, inside the
    # page, and no two on the same spot.
    test "every place is on EMCR's page", %{doc: doc} do
      assert length(doc.places) == 24

      for place <- doc.places do
        assert place.left > 72 and place.left + Map.get(place, :width, place[:size]) < 540,
               place.name

        assert place.top > 72 and place.top < 720, place.name
      end

      spots = Enum.map(doc.places, &{&1.top, &1.left})
      assert Enum.uniq(spots) == spots
    end
  end

  describe "BCSARA's Supplement" do
    setup do
      context = Context.new(SampleRepo.team(), DateTime.utc_now(), repo: SampleRepo)
      {:ok, doc} = "#{@dir}/bcsara/supplement.txt" |> File.read!() |> Document.parse()
      {:ok, doc} = Document.check(doc, context)
      %{doc: doc}
    end

    # Typst draws the blank once, and the PDF is what it drew: change the program, then
    # draw the page again with tools/forms/draw_page.exs.
    test "its page is the blank its Typst program draws" do
      {:ok, drawn} = "#{@dir}/bcsara/supplement.typ" |> File.read!() |> Service.Typst.compile()
      assert drawn == File.read!("#{@dir}/bcsara/supplement.pdf")
    end

    test "asks On task and Meals provided for each person, starting from one for everyone",
         %{doc: doc} do
      assert Enum.map(doc.asks, &{&1.name, &1.each}) == [
               {"meals_provided", nil},
               {"on_task", "people"},
               {"meals_given", "people"}
             ]
    end

    # The claim's rules print here, reading the same answers (#950).
    test "works out each person's total as the claim's rules do", %{doc: doc} do
      {:ok, claim} =
        "test/support/fixtures/forms/claim_rules.txt" |> File.read!() |> Document.parse()

      {:ok, claim} =
        Document.check(
          claim,
          Context.new(SampleRepo.team(), DateTime.utc_now(), repo: SampleRepo)
        )

      person = fn key, km, from, to ->
        %{
          key: key,
          values: %{"member" => key, "km" => km, "started_at" => from, "finished_at" => to}
        }
      end

      values = %{
        "task.`Response Type`" => "Response",
        "people" => [
          person.("member:1", 30, ~U[2026-06-01 15:00:00Z], ~U[2026-06-01 21:30:00Z]),
          person.("member:2", 12, ~U[2026-04-15 06:00:00Z], ~U[2026-04-16 08:00:00Z]),
          person.("member:3", nil, ~U[2026-06-01 15:00:00Z], nil)
        ],
        ":meals_provided" => 1,
        {"on_task", "member:2"} => "No",
        {"meals_given", "member:1"} => 0
      }

      # $75.10 on task for 6.5 hours, $7.80 off task, and nothing for one still out.
      supplement = Document.values(doc, values, "America/Vancouver")
      claimed = Document.values(claim, values, "America/Vancouver")

      assert Service.Format.money(supplement["personnel"]) == "$82.90"
      assert Decimal.eq?(supplement["personnel"], claimed["personnel"])
    end

    test "20 people print two copies of its page, numbered", %{doc: doc} do
      people =
        for i <- 1..20,
            do: %{
              key: "member:#{i}",
              values: %{"member" => "Person #{i}", "started_at" => ~U[2026-06-01 15:00:00Z]}
            }

      output = Document.evaluate(doc, %{"people" => people}, "America/Vancouver")
      page = File.read!("#{@dir}/bcsara/supplement.pdf")

      assert {:ok, pdf} = PrintDocument.call(output, page: page)
      assert Service.PDFPages.count(pdf) == {:ok, 2}
    end
  end
end
