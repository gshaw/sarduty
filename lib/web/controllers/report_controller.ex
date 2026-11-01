defmodule Web.ReportController do
  use Web, :controller

  alias App.Report
  alias App.Report.Error
  alias App.ViewData.ReportRecords
  alias App.ViewData.Reports

  @doc "A report's rows as CSV (#768), run with the values in the URL, as its page shows them."
  def csv(conn, %{"id" => id} = params) do
    team = conn.assigns.current_team
    now = DateTime.utc_now()
    report = Reports.find(team, id, now) || raise Web.Status.NotFound
    given = Map.drop(params, ["subdomain", "id"])
    given = if given == %{}, do: report.values, else: given

    case Report.run(report.query, team, given, now) do
      {:ok, result} ->
        csv = Web.ReportCSV.build(result, ReportRecords.load(result, team, now), team.timezone)

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="#{team.subdomain}-report-#{report.id}.csv")
        )
        |> send_resp(200, csv)

      {:error, %Error{} = error} ->
        send_resp(conn, 422, Error.text(error))
    end
  end
end
