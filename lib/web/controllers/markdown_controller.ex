defmodule Web.MarkdownController do
  use Web, :controller

  alias App.Report.Language

  # Pages as Markdown, for agents: the agents lander (Web.AgentsLive), How to write a
  # report (#803; the page is Web.ReportLanguageLive), How to check an ID card
  # (Web.CardApiLive), and the changelog (Web.ChangelogLive).
  @changelog_path Path.expand("../../../CHANGELOG.md", __DIR__)
  @external_resource @changelog_path
  @changelog File.read!(@changelog_path)

  def agents(conn, _params), do: markdown(conn, Web.AgentsLive.markdown())

  def report_language(conn, _params), do: markdown(conn, Language.markdown())

  def id_cards(conn, _params), do: markdown(conn, Web.CardApiDoc.markdown())

  def changelog(conn, _params), do: markdown(conn, @changelog)

  defp markdown(conn, text) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, text)
  end
end
