defmodule App.FeatureReachTest do
  use ExUnit.Case, async: true

  # Shared code never asks whether a record belongs to one feature (#848). It names the
  # idea on the shared model and lets the feature supply it, as Activity's logged time
  # does for chores. A feature is the modules with its word in their name. Any other
  # module that calls one is listed here with why: a new caller fails until it is listed
  # or finds the shared idea, and a listed file that stops calling fails until it comes
  # off, so the lists only shrink. It reads compiled calls, so copy and docs don't count;
  # struct literals and route modules don't either.
  @features %{
    "Chore" => %{
      "lib/app/coast_range.ex" => "the demo team's sample chores",
      "lib/app/model/activity.ex" => "logged time (#848), the one place shared code reads chores",
      "lib/app/view_data/team_dashboard_view_data.ex" =>
        "the Dashboard's chores to accept and send",
      "lib/web/live/me_live.ex" => "Your membership's chores section",
      "lib/web/live/team_dashboard_live.ex" => "the Dashboard's chores tile"
    },
    "Certificate" => %{
      "lib/app/operation/award_qualification.ex" =>
        "awarding a qualification accepts its waiting certificate (#493)",
      "lib/app/view_data/team_dashboard_view_data.ex" => "the Dashboard's certificates to review",
      "lib/web/controllers/me_controller.ex" => "a member downloads their own certificate",
      "lib/web/controllers/member_controller.ex" => "a team admin downloads a certificate",
      "lib/web/controllers/style_guide_html/sample_data.ex" => "the style guide's sample file",
      "lib/web/live/me_live.ex" => "Your membership's certificates section",
      "lib/web/live/member_qualifications_live.ex" => "a qualification's certificate file",
      "lib/web/live/team_dashboard_live.ex" => "the Dashboard's certificates tile"
    }
  }

  for word <- Map.keys(@features) do
    test "only the listed files outside #{word} call its modules" do
      word = unquote(word)
      listed = @features[word]
      callers = callers(word)

      unlisted = Enum.reject(callers, &Map.has_key?(listed, elem(&1, 0)))

      assert unlisted == [],
             "#{inspect(unlisted, pretty: true)}\nreach into #{word}. Name the idea on the " <>
               "shared model instead (#848), or list the file in @features with why."

      stale = listed |> Map.keys() |> Enum.reject(&List.keymember?(callers, &1, 0))

      assert stale == [],
             "#{inspect(stale)} no longer call #{word}: take them off @features."
    end
  end

  # `{file, [feature modules it calls]}` for every file in lib/ outside the feature.
  defp callers(word) do
    {:ok, modules} = :application.get_key(:sarduty, :modules)

    calls =
      for module <- modules,
          not feature?(module, word),
          file = source(module),
          String.starts_with?(file, "lib/"),
          called <- feature_calls(module, word),
          uniq: true,
          do: {file, called}

    calls |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Enum.sort()
  end

  defp feature?(module, word), do: module |> inspect() |> String.contains?(word)

  # The feature's modules that `module` calls, from its compiled imports.
  defp feature_calls(module, word) do
    {:ok, {^module, [imports: imports]}} =
      module |> :code.which() |> :beam_lib.chunks([:imports])

    imports |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.filter(&feature?(&1, word))
  end

  defp source(module),
    do: module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd()
end
