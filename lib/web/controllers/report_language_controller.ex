defmodule Web.ReportLanguageController do
  use Web, :controller

  alias App.Report.Language

  # How to write a report as Markdown, for agents (#803). The page is Web.ReportLanguageLive.
  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, Language.markdown())
  end
end
