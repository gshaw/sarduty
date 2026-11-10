defmodule App.Operation.EmailTaxCreditLettersTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.Team
  alias App.Operation.EmailTaxCreditLetters

  @avery %Member{id: 1, name: "Avery", email: "avery@example.com"}
  @blake %Member{id: 2, name: "Blake", email: nil}

  # What Email does for a member whose letter is where `attrs` say.
  defp what(attrs), do: attrs |> record() |> EmailTaxCreditLetters.what()

  # Where a member's letter is, as Email reads it.
  defp record(attrs) do
    Map.merge(
      %{member: @avery, letter: %PublishedPDF{email_status: nil}, changes: [], total_minutes: 90},
      Map.new(attrs)
    )
  end

  describe "what/1: what Email does for a member (#995)" do
    test "no letter, or one out of date, is published first" do
      assert what(letter: nil) == :first

      assert what(changes: ["Total hours: 1 hour → 2 hours"]) ==
               :replace

      assert EmailTaxCreditLetters.publishes?(:first) and
               EmailTaxCreditLetters.publishes?(:replace)
    end

    test "an up-to-date letter goes as it is, emailed or not, and again" do
      assert what(%{}) == :not_emailed

      assert what(letter: %PublishedPDF{email_status: :failed}) ==
               :failed

      assert what(letter: %PublishedPDF{email_status: :sent}) ==
               :again

      refute EmailTaxCreditLetters.publishes?(:again)
    end

    test "a member with no email gets a letter published, and nothing more" do
      assert what(member: @blake, letter: nil) == :first

      assert what(member: @blake, changes: ["Name: Bleak → Blake"]) ==
               :replace

      assert what(member: @blake) == nil
      refute EmailTaxCreditLetters.emailed?(@blake)
    end

    test "not offered with no hours, or while its email waits" do
      assert what(letter: nil, total_minutes: 0) == nil

      assert what(letter: %PublishedPDF{email_status: :sending}) ==
               nil
    end
  end

  test "a year that isn't over in the team's time zone is early, refused without early: true" do
    team = %Team{timezone: "America/Vancouver"}
    # The evening of December 31, 2026 in Vancouver: 2026 isn't over there yet.
    evening = ~U[2027-01-01 05:00:00Z]

    assert EmailTaxCreditLetters.early?(2026, team, evening)
    refute EmailTaxCreditLetters.early?(2026, team, ~U[2027-01-01 09:00:00Z])

    assert EmailTaxCreditLetters.refusal(2026, team, evening, nil) ==
             "2026 isn't over. Email sends its letters only once you tick that it's early."

    assert EmailTaxCreditLetters.refusal(2026, team, evening, true) == nil
    assert EmailTaxCreditLetters.refusal(2025, team, evening, nil) == nil
  end

  test "summarizes what each member got" do
    results = [
      {@avery, {:published, :emailing}},
      {@blake, {:published, :no_email}},
      {%Member{id: 3}, :emailing},
      {%Member{id: 4}, {:refused, "This letter cannot be published without the signer."}},
      {%Member{id: 5}, :stale},
      {%Member{id: 6}, :skipped}
    ]

    assert %{
             year: 2025,
             published: 2,
             emailing: 2,
             not_emailed: [@blake],
             refused: [{%Member{id: 4}, "This letter cannot be published without the signer."}],
             stale: 1
           } = EmailTaxCreditLetters.summarize(results, 2025)
  end
end
