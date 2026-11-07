defmodule App.FormsTest do
  # Each organization's form in priv/forms, as a SAR Duty admin uploads it (#950): its
  # text and its page save, which checks them on Coast Range SAR and runs every expect,
  # and it prints there. Coast Range SAR's own database only reads.
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Document
  alias App.Operation.SaveForm
  alias App.Operation.TryForm
  alias App.Report.Query

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
end
