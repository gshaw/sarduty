defmodule App.Operation.BuildTaxCreditLetterAttachmentTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Operation.BuildTaxCreditLetterAttachment

  setup do
    team = team_fixture()

    letter =
      team |> member_fixture() |> tax_credit_letter_fixture() |> Repo.preload(member: :team)

    %{team: team, letter: letter}
  end

  test "draws a tall logo, padded square", %{team: team, letter: letter} do
    team_logo_fixture(team, png_fixture(1500, 1740))

    attachment = BuildTaxCreditLetterAttachment.call(letter)

    assert attachment.content =~ "%PDF"
    assert attachment.content =~ "/Subtype /Image"
  end

  test "a team without a logo gets none, not SAR Duty's", %{letter: letter} do
    attachment = BuildTaxCreditLetterAttachment.call(letter)
    refute attachment.content =~ "/Subtype /Image"
  end
end
