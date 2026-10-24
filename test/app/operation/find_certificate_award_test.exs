defmodule App.Operation.FindCertificateAwardTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.QualificationAward
  alias App.Operation.FindCertificateAward

  # Which day an award starts on is QualificationAward.starts_on?/2's test.
  test "the member's award of the same qualification that starts the same day" do
    # D4H keeps an award's start at midnight UTC.
    same = %QualificationAward{
      d4h_award_id: 1,
      d4h_qualification_id: 4,
      starts_at: ~U[2026-10-18 00:00:00Z]
    }

    earlier = %{same | d4h_award_id: 2, starts_at: ~U[2025-10-18 00:00:00Z]}
    other = %{same | d4h_award_id: 3, d4h_qualification_id: 5}

    assert FindCertificateAward.match([earlier, other, same], 4, ~D[2026-10-18]) == same
    assert FindCertificateAward.match([earlier, other], 4, ~D[2026-10-18]) == nil
  end
end
