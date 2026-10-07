defmodule App.Operation.BuildTaxCreditLetterAttachmentTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Operation.BuildTaxCreditLetterAttachment
  alias App.Operation.CreateTaxCreditLetter
  alias App.Operation.SaveTeamSignature

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

  describe "the signature" do
    setup %{team: team} do
      member = member_fixture(team)
      %{member: member}
    end

    defp create_letter(team, member) do
      CreateTaxCreditLetter.call(team: Repo.reload!(team), member_id: member.id, year: 2025)
    end

    defp images(attachment) do
      parts = String.split(attachment.content, "/Subtype /Image")
      length(parts) - 1
    end

    test "a letter made with a signature draws it", %{team: team, member: member} do
      {:ok, _team} = SaveTeamSignature.call(team, png_fixture(600, 150))

      attachment = team |> create_letter(member) |> BuildTaxCreditLetterAttachment.call()

      assert attachment.content =~ "%PDF"
      assert images(attachment) == 1
    end

    test "a letter keeps the signature it was made with", %{team: team, member: member} do
      {:ok, _team} = SaveTeamSignature.call(team, png_fixture(600, 150))
      letter = create_letter(team, member)
      first = letter.signature

      {:ok, _team} = team |> Repo.reload!() |> SaveTeamSignature.call(png_fixture(400, 200))

      assert letter |> Repo.reload!() |> Map.fetch!(:signature) == first
      assert images(BuildTaxCreditLetterAttachment.call(letter)) == 1
    end

    test "a letter made before the team had a signature stays unsigned",
         %{team: team, member: member} do
      letter = create_letter(team, member)
      {:ok, _team} = SaveTeamSignature.call(team, png_fixture(600, 150))

      letter = letter |> Repo.reload!() |> Repo.preload(member: :team)
      assert images(BuildTaxCreditLetterAttachment.call(letter)) == 0
    end

    test "old letter text with no gap to sign in is drawn unsigned", %{letter: letter} do
      letter = %{letter | signature: png_fixture(600, 150)}
      assert images(BuildTaxCreditLetterAttachment.call(letter)) == 0
    end
  end
end
