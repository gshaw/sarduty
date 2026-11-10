# cspell:ignore Łukasz Nowak Nguyễn Văn -- names past WinAnsi (#917)
defmodule App.Operation.PrintTaxCreditLetterTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.PublishedPDF
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.PublishTaxCreditLetter
  alias App.Operation.SaveTeamSignature

  setup do
    team = team_fixture()
    %{team: team, member: member_fixture(team)}
  end

  defp create(team, member) do
    team
    |> Repo.reload!()
    |> PublishTaxCreditLetter.prepare(member.id, 2025, nil)
    |> PublishTaxCreditLetter.insert!(nil)
  end

  # The PDF as it was published.
  defp print(letter), do: PublishedPDF.attachment(letter)

  defp text(team, member) do
    team = Repo.reload!(team)

    PrintTaxCreditLetter.text(
      team,
      PrintTaxCreditLetter.read(team, member.id, 2025, DateTime.utc_now())
    )
  end

  # Pictures on the page. A picture with an alpha channel stores it as a second image,
  # its /SMask. PDFLock encrypts strings and streams, so the dictionaries still read.
  defp images(%{content: pdf}), do: count(pdf, "/Subtype/Image") - count(pdf, "/SMask")

  defp count(content, pattern), do: length(String.split(content, pattern)) - 1

  test "prints a name past Western European letters (#917)", %{team: team} do
    for name <- ["Łukasz Nowak", "Nguyễn Văn An"] do
      member = member_fixture(team, %{name: name})

      assert text(team, member) =~ "Name: #{name}\n"
      assert %{content: "%PDF" <> _rest} = team |> create(member) |> print()
    end
  end

  test "titles the PDF and locks it print-only", %{team: team, member: member} do
    attachment = team |> create(member) |> print()

    assert attachment.title == "2025 SRVTC #{team.legal_name}"
    assert attachment.filename =~ ~r/^2025_SRVTC_.*\.pdf$/
    assert attachment.content =~ "/Encrypt"
    assert {:ok, _key} = Service.PDFLock.file_key(attachment.content)
  end

  describe "the letterhead" do
    test "a team without a logo gets none, not SAR Duty's", %{team: team, member: member} do
      assert team |> create(member) |> print() |> images() == 0
    end

    test "prints the team's logo, padded square", %{team: team, member: member} do
      team_logo_fixture(team, png_fixture(1500, 1740))
      assert team |> create(member) |> print() |> images() == 1
    end

    test "puts the organization's logo beside the team's", %{team: team, member: member} do
      organization_fixture([team])
      team_logo_fixture(team, png_fixture(300, 150))
      assert team |> create(member) |> print() |> images() == 2
    end

    test "leaves out the organization's when it has none", %{team: team, member: member} do
      organization_fixture([team], %{logo: nil})
      assert team |> create(member) |> print() |> images() == 0
    end
  end

  describe "the signature" do
    test "prints the team's signature", %{team: team, member: member} do
      {:ok, _team} = SaveTeamSignature.call(team, png_fixture(600, 150))

      assert images(print(create(team, member))) == 1
      # The picture takes the place of the blank lines left to sign in.
      refute text(team, member) =~ "\n\n\n\n"
    end

    test "leaves room to sign without one", %{team: team, member: member} do
      assert images(print(create(team, member))) == 0
      assert text(team, member) =~ ~r/Certified on .*\.\n\n\n\n\n#{team.legal_name}/
    end
  end

  test "prints under the ID it's published with, and keeps 0 for no hours (#970)",
       %{team: team, member: member} do
    read = PrintTaxCreditLetter.read(team, member.id, 2025, DateTime.utc_now())
    {:ok, printed} = PrintTaxCreditLetter.call(team, read, "K7Q4M2XA9HVB3TN")

    assert printed.code == "K7Q4M2XA9HVB3TN"
    assert printed.name == "Tax credit letter"
    assert printed.keep == %{"hours.primary" => 0, "hours.secondary" => 0}
    assert %{content: "%PDF" <> _rest} = printed.attachment
  end

  test "names the settings it needs that the team hasn't filled in (#943, #970)", %{team: team} do
    team =
      team
      |> Ecto.Changeset.change(
        mailing_address: nil,
        authorized_by_name: "Pat Lee",
        signature: nil
      )
      |> Repo.update!()

    assert PrintTaxCreditLetter.missing_settings(team, DateTime.utc_now()) ==
             ["mailing address", "signature"]
  end

  test "a Try a demo team's letter says SAMPLE across it (#857)", %{team: team, member: member} do
    real = team |> create(member) |> print()
    demo_team_fixture(team)
    sample = team |> create(member_fixture(team)) |> print()

    assert images(real) == 0
    assert images(sample) == 1
  end
end
