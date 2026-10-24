defmodule Web.CertificateController do
  use Web, :controller

  alias App.Model.Certificate
  alias App.Model.Team

  # A member's sent certificate (#493) for a team admin, looked up through the team,
  # while SAR Duty keeps its file.
  def file(conn, %{"id" => id}) do
    team = conn.assigns.current_team
    if !Team.certificates?(team), do: raise(Web.Status.NotFound)
    Web.CertificateResponse.send_sent(conn, Certificate.find!(team, id))
  end
end
