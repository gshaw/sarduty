defmodule App.ViewData.TeamAttentionTest do
  use ExUnit.Case, async: true

  alias App.ViewData.TeamAttention

  # 9 a.m. on October 6 in Vancouver: not letter season.
  @october ~U[2026-10-06 16:00:00Z]
  # 9 a.m. on March 2 in Vancouver.
  @march ~U[2026-03-02 17:00:00Z]

  defp rows(attrs) do
    Map.merge(
      %{
        timezone: "America/Vancouver",
        refresh: %{state: :ok, message: nil},
        draft_count: 0,
        expiring_days: 60,
        expiring_count: 0,
        missing_details_count: 0,
        group_change_count: 0,
        proposed_change_count: 0,
        letters: nil
      },
      attrs
    )
  end

  # The items for these counts, with every other count at zero.
  defp items(attrs, now), do: attrs |> rows() |> TeamAttention.items(now)

  defp keys(items), do: Enum.map(items, & &1.key)

  test "nothing to do means no items" do
    assert items(%{}, @october) == []
  end

  test "each count shows its item, warnings first" do
    items =
      items(
        %{
          group_change_count: 2,
          missing_details_count: 9,
          expiring_count: 6,
          draft_count: 3,
          refresh: %{state: :failed, message: "D4H rejected the team key (401)."}
        },
        @october
      )

    assert keys(items) == [:refresh, :drafts, :expiring, :missing_details, :group_changes]
    assert Enum.map(items, & &1.level) == [:warning, :warning, :warning, :info, :info]
  end

  test "titles carry the count, with the noun agreeing" do
    one = items(%{draft_count: 1, missing_details_count: 1}, @october)
    many = items(%{draft_count: 3, missing_details_count: 9}, @october)

    assert Enum.map(one, & &1.title) == [
             "1 draft activity",
             "1 member has no email or mobile phone"
           ]

    assert Enum.map(many, & &1.title) == [
             "3 draft activities",
             "9 members have no email or mobile phone"
           ]

    assert [%{title: "6 qualifications expire within 60 days"}] =
             items(%{expiring_count: 6}, @october)
  end

  test "a failed refresh shows D4H's reason; a rejected key alone says so too" do
    failed = %{refresh: %{state: :failed, message: "No D4H key."}}
    assert [%{key: :refresh, detail: "No D4H key."}] = items(failed, @october)

    rejected = %{refresh: %{state: :key_rejected, message: nil}}
    assert [%{key: :refresh, detail: detail}] = items(rejected, @october)
    assert detail == "Your D4H access key no longer works."

    assert items(%{refresh: %{state: :refreshing, message: nil}}, @october) ==
             []
  end

  test "tax credit letters show from January to April only, in the team's zone" do
    letters = %{letters: %{year: 2025, count: 11}}

    assert [%{key: :letters, year: 2025, title: "11 tax credit letters to create for 2025"}] =
             items(letters, @march)

    assert items(letters, @october) == []
    # 5 p.m. on April 30 in Vancouver, already May 1 in UTC.
    assert [%{key: :letters}] = items(letters, ~U[2026-05-01 00:30:00Z])
    assert items(%{letters: %{year: 2025, count: 0}}, @march) == []
  end

  test "every item can show at once" do
    everything =
      %{
        refresh: %{state: :failed, message: "No D4H key."},
        draft_count: 1,
        expiring_count: 1,
        missing_details_count: 1,
        group_change_count: 1,
        proposed_change_count: 1,
        letters: %{year: 2025, count: 1}
      }

    assert everything |> items(@march) |> length() == 7
  end

  test "a team without D4H fixes things in SAR Duty, so no item sends it to D4H" do
    attrs = %{hosted?: true, draft_count: 2, expiring_count: 1, missing_details_count: 3}

    for item <- items(attrs, @october) do
      refute item.detail =~ "D4H", item.title
    end
  end
end
