defmodule App.Operation.ReadDocumentTest do
  # Reads Coast Range SAR's own database (#816). No sandbox: it only reads, as every
  # sample run does.
  use ExUnit.Case, async: true

  import Ecto.Query

  alias App.Document
  alias App.Model.Activity
  alias App.Operation.ReadDocument
  alias App.Report.Context
  alias App.SampleRepo

  @claim File.read!("priv/forms/bcsara/expense_request.txt")

  defp context, do: Context.new(SampleRepo.team(), DateTime.utc_now(), repo: SampleRepo)

  defp incident do
    team = SampleRepo.team()

    query = from(a in Activity, where: a.team_id == ^team.id and a.title == "Overdue kayakers")
    query |> limit(1) |> SampleRepo.one!()
  end

  test "a report with a row each reads every row, by its member or item" do
    context = context()

    assert {:ok, %{doc: doc, values: values, read: read}} =
             ReadDocument.call(@claim, context, %{activity: incident().id})

    # The rows show with the form's rows, not as values filled in.
    names = Enum.map(read, & &1.name)
    assert "task.`Response Type`" in names and "team.city" in names
    refute Enum.any?(names, &String.starts_with?(&1, ["people.", "equipment."]))

    assert [_ | _] = people = values["people"]
    assert Enum.all?(people, &(&1.key =~ ~r/^member:\d+$/ and is_binary(&1.values["member"])))
    assert Enum.uniq_by(people, & &1.key) == people

    assert [_ | _] = equipment = values["equipment"]
    assert Enum.all?(equipment, &(&1.key =~ ~r/^item:\d+$/))

    worked = Document.values(doc, values, context.timezone)
    totals = Enum.map(worked["people"], & &1.values["total"])

    assert Enum.all?(totals, &Decimal.gt?(&1, 0))
    assert Decimal.eq?(worked["personnel"], Enum.reduce(totals, &Decimal.add/2))

    assert Decimal.eq?(worked["total"], Decimal.add(worked["subtotal"], worked["ohs_total"]))
  end
end
