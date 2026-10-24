defmodule Web.ServiceNameTest do
  use ExUnit.Case, async: true

  # A team on SAR Duty Records reads the same pages as a D4H team, so text names the
  # service only where the reader must go there, and takes the name from the team:
  # `@service` on a team page, `D4H.service_name/1` elsewhere (docs/writing.md). A
  # "D4H" written into a string or HEEx text fails here. `D4H.` calls, comments, and docs
  # are code, not text.
  @word ~r/(?<![\w.])D4H(?![\w]|\.\w)/

  # Files that may name D4H, and why.
  @files %{
    "lib/app/adapter/" => "the adapter is D4H; its names and errors are for us",
    "lib/app/mcp/tool/" => "tool descriptions are for agents, shared by every team",
    "lib/app/operation/sign_up_team.ex" => "signup's D4H path",
    "lib/app/view_model/event_filter_view_model.ex" => "event labels on /admin/events",
    "lib/app/view_model/team_signup_view_model.ex" => "signup's D4H region",
    "lib/web/components/home_mockups.ex" => "design mockups, not the app",
    "lib/web/controllers/style_guide_html/pages/colour.html.heex" =>
      "the activity colours are D4H's own, and the page says so",
    "lib/web/live/admin/" => "SAR Duty admin pages may use internals",
    "lib/web/live/admin_dashboard_live.ex" => "a SAR Duty admin page",
    "lib/web/live/home_page_live.ex" => "a public page about D4H itself",
    "lib/web/live/privacy_live.ex" => "a public page about D4H itself",
    "lib/web/live/team_signup_live.ex" => "signup asks which service the team uses",
    "lib/web/live/terms_live.ex" => "a public page about D4H itself",
    "lib/web/live/user_login_code_live.ex" => "a public page about D4H itself",
    "lib/web/live/user_login_live.ex" => "a public page about D4H itself",
    "lib/web/live/verify_live.ex" => "a public page about D4H itself"
  }

  # Lines elsewhere that may name D4H, as {file, the text or texts in the line}, and why.
  @lines %{
    {"lib/web/components/layouts.ex", "teams that use D4H"} =>
      "the public description of SAR Duty, about D4H itself",
    {"lib/web/live/settings/team_live.ex",
     ["every D4H request", "the D4H member", "D4H member named", "In D4H, add", "a D4H access"]} =>
      "a D4H team's key steps in team settings, which send the reader to D4H",
    {"lib/web/controllers/style_guide_html", "Open in D4H"} =>
      "the style guide's example of a link that sends the reader to D4H",
    {"lib/web/controllers/style_guide_html/pages/detail_list.html.heex", "Open D4H activity"} =>
      "the same, as a D4H team reads it",
    {"lib/web/controllers/style_guide_html/pages/forms.html.heex", "From D4H. Change it there."} =>
      "a read-only field's hint, which sends the reader to D4H",
    {"lib/web/controllers/style_guide_html/pages/row_link.html.heex", "in D4H."} =>
      "Needs attention as a D4H team reads it, which sends the reader there",
    {"lib/web/controllers/style_guide_html/pages/warning_text.html.heex",
     "Unpublish it in D4H first."} => "a warning that sends the reader to D4H"
  }

  test "text names D4H only through the team's service name" do
    hits =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          not allowed_file?(path),
          {line, number} <- path |> File.read!() |> text_lines(),
          Regex.match?(@word, line),
          not allowed_line?(path, line),
          do: "#{path}:#{number}: #{String.trim(line)}"

    assert hits == [],
           "Say what changed, not where, or name the service with @service or " <>
             "D4H.service_name/1 where the reader must go there (docs/writing.md):\n" <>
             Enum.join(hits, "\n")
  end

  defp allowed_file?(path), do: @files |> Map.keys() |> Enum.any?(&String.starts_with?(path, &1))

  defp allowed_line?(path, line) do
    @lines
    |> Map.keys()
    |> Enum.any?(fn {prefix, text} ->
      String.starts_with?(path, prefix) and String.contains?(line, text)
    end)
  end

  # Numbered lines people read: not comments, docs (heredocs included), or log calls.
  defp text_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_reduce(false, fn {line, number}, in_doc? ->
      trimmed = String.trim(line)
      opens_doc? = Regex.match?(~r/^@(module)?doc\s+(~[sS])?"""/, trimmed)

      cond do
        in_doc? -> {nil, trimmed != ~s(""")}
        opens_doc? -> {nil, true}
        String.starts_with?(trimmed, ["#", "@doc", "@moduledoc", "<%!--"]) -> {nil, false}
        String.contains?(line, ["Logger.", "doc:"]) -> {nil, false}
        true -> {{line, number}, false}
      end
    end)
    |> elem(0)
    |> Enum.reject(&is_nil/1)
  end
end
