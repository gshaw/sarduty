defmodule Web.MarkdownController do
  use Web, :controller

  alias App.Report.Language

  # Pages as Markdown, for agents: How to write a report (#803; the page is
  # Web.ReportLanguageLive) and the changelog (Web.ChangelogLive).
  @changelog_path Path.expand("../../../CHANGELOG.md", __DIR__)
  @external_resource @changelog_path
  @changelog File.read!(@changelog_path)

  def report_language(conn, _params), do: markdown(conn, Language.markdown())

  def changelog(conn, _params), do: markdown(conn, @changelog)

  defp markdown(conn, text) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, text)
  end
end
