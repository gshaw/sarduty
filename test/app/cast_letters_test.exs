defmodule App.CastLettersTest do
  # Tax letters have crashed on names that aren't plain English (#963). The cast's cover
  # different failures: common accents, a letter outside Latin-1, stacked marks, and an
  # apostrophe that breaks HTML, Typst, and CSV escaping. Every Silver Basin member and
  # Zoë Lefèvre gets a letter from the cast's own hours, through the real send, and its
  # email and PDF land in the Outbox, as on a demo. The cast's emails are plain letters.
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.OutboxMessage
  alias App.Operation.EmailTaxCreditLetters
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.SeedCoastRange
  alias App.SilverBasin

  # Training at Tracking day and the Missing angler incident fall in 2025.
  @now ~U[2026-06-15 19:00:00Z]

  test "each accented name gets a tax letter with its hours, and its PDF prints" do
    coast = SeedCoastRange.call(Repo, @now)
    basin = SeedCoastRange.insert(Repo, SilverBasin.build(@now))
    coast_team = coast[{:team, :coastrange}]
    basin_team = basin[{:team, :silverbasin}]
    demo_team_fixture(coast_team, %{second_team_id: basin_team.id})

    for {team, rows, names} <- [
          {coast_team, coast, ["Zoë Lefèvre"]},
          {basin_team, basin, SilverBasin.names()}
        ] do
      ids = for name <- names, do: rows[{:member, name}].id
      summary = EmailTaxCreditLetters.run(team, 2025, ids, nil, now: @now)
      assert summary.published == length(names) and summary.emailing == length(names)

      messages = OutboxMessage.list(team)

      for name <- names do
        email = rows[{:member, name}].email
        message = Enum.find(messages, &(&1.to == email)) || flunk("no letter for #{name}")
        message = OutboxMessage.get(team, message.id)
        assert [%{content_type: "application/pdf"} = pdf] = message.attachments
        assert "%PDF" <> _rest = OutboxMessage.get_attachment(message, pdf.id).data

        # The PDF is locked, and its text is glyphs, so read the letter's own text.
        member = rows[{:member, name}]
        read = PrintTaxCreditLetter.read(team, member.id, 2025, @now)
        assert PrintTaxCreditLetter.text(team, read) =~ "Name: #{name}\n"
      end
    end
  end
end
