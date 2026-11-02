defmodule Web.ReportController do
  use Web, :controller

  alias App.Report
  alias App.Report.Error
  alias App.Report.Lists
  alias App.ViewData.ReportRecords
  alias App.ViewData.Reports

  @doc """
  A report's rows as CSV (#768), run with the picks in the URL, every page of them. A list
  on the report engine, such as Activities, downloads the same way by its slug (#784).
  """
  def csv(conn, %{"id" => id} = params) do
    team = conn.assigns.current_team
    now = DateTime.utc_now()
    report = Reports.find(team, id, now) || list(id) || raise Web.Status.NotFound
    # The URL's picks, over the ones saved with the report, as its page runs it.
    given = Map.merge(report.values, Map.drop(params, ["subdomain", "id"]))

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

  defp list(slug) do
    case Lists.get(slug) do
      nil -> nil
      list -> %{id: list.slug, query: list.query, values: %{}}
    end
  end
end
