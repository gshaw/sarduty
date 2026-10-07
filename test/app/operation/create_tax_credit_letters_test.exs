defmodule App.Operation.CreateTaxCreditLettersTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Operation.CreateTaxCreditLetters

  @avery %Member{id: 1, name: "Avery"}
  @blake %Member{id: 2, name: "Blake"}
  @casey %Member{id: 3, name: "Casey"}

  test "picks members with no letter for the year yet" do
    assert CreateTaxCreditLetters.pick([@avery, @blake, @casey], [2]) == [@avery, @casey]
    assert CreateTaxCreditLetters.pick([@avery], []) == [@avery]
    assert CreateTaxCreditLetters.pick([@avery], [1]) == []
  end

  test "counts letters made and emailed, and names who had no email or a failed one" do
    summary =
      CreateTaxCreditLetters.summarize(
        [{@avery, :ok}, {@blake, {:error, :no_email}}, {@casey, {:error, :timeout}}],
        2025
      )

    assert summary == %{
             year: 2025,
             created: 3,
             emailed: 1,
             no_email: [@blake],
             failed: [@casey]
           }
  end

  test "nothing to send is an empty summary" do
    assert %{created: 0, emailed: 0, no_email: [], failed: []} =
             CreateTaxCreditLetters.summarize([], 2025)
  end
end
