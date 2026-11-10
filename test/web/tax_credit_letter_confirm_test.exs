defmodule Web.TaxCreditLetterConfirmTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias Web.TaxCreditLetterConfirm

  defp record(n),
    do: %{
      member: %Member{id: n, name: "Member #{n}", email: "member#{n}@example.com"},
      letter: nil,
      email: :first,
      total_minutes: 90
    }

  test "early, a box from 1 says so, and from 10 it says the count too (#995)" do
    one = TaxCreditLetterConfirm.email([record(1)], 2026, true)

    assert one["data-confirm-check"] ==
             "I know the 2026 tax year isn't over. I'm emailing early to test."

    ten = 1..10 |> Enum.map(&record/1) |> TaxCreditLetterConfirm.email(2026, true)

    assert ten["data-confirm-check"] ==
             "I know the 2026 tax year isn't over. I'm emailing 10 members early to test."

    assert ten["data-confirm-warning"] =~ "make these letters out of date"
    assert ten["data-confirm-warning"] =~ "Emails cannot be taken back."

    # Once the year is over, the box waits for 10 emails, as every send does.
    over = TaxCreditLetterConfirm.email([record(1)], 2025)
    refute Map.has_key?(over, "data-confirm-check")
  end
end
