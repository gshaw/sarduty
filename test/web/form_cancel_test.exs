defmodule Web.FormCancelTest do
  @moduledoc """
  A form on a page of its own gets a Cancel button that goes back where the link came from
  (/styles/button#cancel). A LiveView with a button row and no Cancel link saves in place,
  and says why here.
  """
  use ExUnit.Case, async: true

  @root "../.." |> Path.expand(__DIR__)

  @in_place %{
    "lib/web/live/activity_attendance_live.ex" =>
      "the review step's Cancel returns to the list on the same page",
    "lib/web/live/agent_authorize_live.ex" =>
      "Allow and Cancel both post, so Cancel can send the agent access denied",
    "lib/web/live/admin/team_live.ex" => "login grants are added on the team's admin page",
    "lib/web/live/certificate_live.ex" => "accept, decline, and rotate on the certificate's page",
    "lib/web/live/chore_collection_live.ex" => "accepts the chores ticked in the list",
    "lib/web/live/chore_live.ex" => "accept and decline on the chore's page",
    "lib/web/live/endorsement_collection_live.ex" => "ID card ticks saved on the list",
    "lib/web/live/me_details_live.ex" => "Your details tab, saved in place",
    "lib/web/live/member_card_live.ex" => "ID card actions on the member's tab",
    "lib/web/live/member_qualifications_live.ex" => "awards on the member's tab",
    "lib/web/live/member_standing_live.ex" => "away periods and check-ins on the member's tab",
    "lib/web/live/org/admins_live.ex" => "organization settings tab",
    "lib/web/live/org/hours_tags_live.ex" => "organization settings tab",
    "lib/web/live/org/settings_live.ex" => "organization settings tab",
    "lib/web/live/settings/hours_tags_live.ex" => "team settings tab",
    "lib/web/live/settings/tax_credit_letters_live.ex" => "team settings tab",
    "lib/web/live/settings/members_live.ex" => "team settings tab",
    "lib/web/live/settings/team_live.ex" => "team settings tab",
    "lib/web/live/tax_credit_letter_live.ex" => "Download PDF on the letter's page, not a form",
    "lib/web/live/team_signup_live.ex" => "signing up has no page to go back to",
    "lib/web/live/user_login_code_live.ex" => "logging in has no page to go back to",
    "lib/web/live/user_login_live.ex" => "logging in has no page to go back to"
  }

  test "every form page has a Cancel link, or a reason it saves in place" do
    found =
      for file <- @root |> Path.join("lib/web/live/**/*.ex") |> Path.wildcard(),
          source = File.read!(file),
          source =~ "<.form_actions",
          not (source =~ ~r/<\.button\b[^>]*\bnavigate=[^>]*>\s*Cancel\s*<\/\.button>/s),
          do: Path.relative_to(file, @root)

    unlisted = Enum.reject(found, &Map.has_key?(@in_place, &1))

    assert unlisted == [],
           "Give the form a <.button navigate={…}>Cancel</.button> after its main button, " <>
             "or add why it saves in place here:\n" <> Enum.join(unlisted, "\n")

    stale = Map.keys(@in_place) -- found
    assert stale == [], "Has a Cancel link now, or is gone, so remove: #{inspect(stale)}"
  end
end
