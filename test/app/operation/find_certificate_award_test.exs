defmodule App.Operation.FindCertificateAwardTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.QualificationAward
  alias App.Operation.FindCertificateAward

  @tz "America/Vancouver"

  test "the award of the same qualification that starts the same day on the team's clock" do
    # 17:00 on Oct 17 in Vancouver is Oct 18 in UTC: a different day here.
    evening = %QualificationAward{
      d4h_award_id: 1,
      d4h_qualification_id: 4,
      starts_at: ~U[2026-10-18 00:00:00Z]
    }

    midnight = %{evening | d4h_award_id: 2, starts_at: ~U[2026-10-18 07:00:00Z]}
    other = %{midnight | d4h_award_id: 3, d4h_qualification_id: 5}

    assert FindCertificateAward.match([evening, other, midnight], 4, ~D[2026-10-18], @tz) ==
             midnight

    assert FindCertificateAward.match([evening, other], 4, ~D[2026-10-18], @tz) == nil
  end
end
