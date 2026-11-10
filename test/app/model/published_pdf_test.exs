defmodule App.Model.PublishedPDFTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.PublishedPDF

  # cspell:ignore ABCDEFGHJKMNPQRSTVWXYZ -- the code alphabet
  describe "IDs" do
    test "a new one is 15 characters from the ID card alphabet, shown 5-5-5" do
      code = PublishedPDF.generate_code()
      assert code =~ ~r/^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{15}$/
      assert PublishedPDF.parse_code(code) == code
      assert PublishedPDF.format_code("K7Q4M2XA9HVB3TN") == "K7Q4M-2XA9H-VB3TN"
    end

    test "case, spaces, and dashes do not matter" do
      for typed <- ["k7q4m-2xa9h-vb3tn", " K7Q4M 2XA9H VB3TN ", "K7Q4M2XA9HVB3TN"] do
        assert PublishedPDF.parse_code(typed) == "K7Q4M2XA9HVB3TN", typed
      end
    end

    test "anything else is nil: a card's code, and a letter's from before #970" do
      for typed <-
            [
              "",
              "K7Q4M2XA",
              "K7Q4M2XA9H",
              "K7Q4M2XA9HVB3T0",
              "SRVTC-K7Q4M2XA",
              "SRVTC-M4K11",
              nil
            ] do
        assert PublishedPDF.parse_code(typed) == nil, inspect(typed)
      end
    end

    test "the verify link is the root of the verify site" do
      assert PublishedPDF.verify_link("K7Q4M2XA9HVB3TN") ==
               "#{Web.VerifyHost.url()}/K7Q4M-2XA9H-VB3TN"
    end
  end

  describe "publish/3" do
    setup do
      team = team_fixture()
      %{team: team, member: member_fixture(team)}
    end

    defp attrs(team, code),
      do: %{team_id: team.id, name: "Task report", subject: "activity:1", code: code}

    defp printed(text),
      do: %{
        attachment: %{content: "%PDF #{text}", title: text, filename: "#{text}.pdf"},
        keep: %{"total" => 3},
        shows: [%{"label" => "Total", "text" => "3"}]
      }

    test "saves the PDF, what it keeps and shows, and its checksum", %{team: team} do
      {:ok, pdf} = team |> attrs("K7Q4M2XA9HVB3TN") |> PublishedPDF.publish(printed("one"), nil)

      assert PublishedPDF.status(pdf) == :current
      assert pdf.keep == %{"total" => 3}
      assert pdf.sha256 == :sha256 |> :crypto.hash("%PDF one") |> Base.encode16(case: :lower)
      assert PublishedPDF.attachment(pdf).content == "%PDF one"
    end

    test "publishing again replaces the current one, which stays", %{team: team} do
      {:ok, first} = team |> attrs("K7Q4M2XA9HVB3TN") |> PublishedPDF.publish(printed("one"), nil)

      {:ok, second} =
        team |> attrs("M2XA9HVB3TNK7Q4") |> PublishedPDF.publish(printed("two"), first.id)

      first = Repo.reload!(first)
      assert first.replaced_by_id == second.id
      assert PublishedPDF.status(first) == :replaced
      assert PublishedPDF.get_current(team.id, "Task report", "activity:1").id == second.id
    end

    test "when another published meanwhile, nothing is saved", %{team: team} do
      {:ok, _first} =
        team |> attrs("K7Q4M2XA9HVB3TN") |> PublishedPDF.publish(printed("one"), nil)

      assert team |> attrs("M2XA9HVB3TNK7Q4") |> PublishedPDF.publish(printed("two"), nil) ==
               {:error, :stale}

      refute Repo.get_by(PublishedPDF, code: "M2XA9HVB3TNK7Q4")
    end
  end

  describe "find_for_verify/2" do
    test "finds a letter by its ID, with its team and what replaced it" do
      team = team_fixture()
      member = member_fixture(team)
      letter = tax_credit_letter_fixture(member, %{code: "K7Q4M2XA9HVB3TN"})

      pdf = PublishedPDF.find_for_verify("K7Q4M2XA9HVB3TN")
      assert pdf.id == letter.id
      assert pdf.team.id == team.id
      refute PublishedPDF.find_for_verify("K7Q4M2XA9HVB3TM")
    end
  end
end
