defmodule Web.ReportController do
  use Web, :controller

  alias App.Report
  alias App.Report.BuiltIn
  alias App.Report.Error
  alias App.ViewData.ReportRecords

  @doc "A report's rows as CSV (#768), run with the values in the URL, as its page shows them."
  def csv(conn, %{"slug" => slug} = params) do
    report = BuiltIn.get(slug) || raise Web.Status.NotFound
    team = conn.assigns.current_team
    now = DateTime.utc_now()

    case Report.run(report.query, team, Map.drop(params, ["subdomain", "slug"]), now) do
      {:ok, result} ->
        csv = Web.ReportCSV.build(result, ReportRecords.load(result, team, now), team.timezone)

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{slug}.csv"))
        |> send_resp(200, csv)

      {:error, %Error{} = error} ->
        send_resp(conn, 422, Error.text(error))
    end
  end
end
