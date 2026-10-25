defmodule Web.CertificateCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.StatSwitch

  alias App.Model.Certificate
  alias App.Model.Team
  alias Service.Format
  alias Web.CertificateText

  # The certificates members sent (#493), /teams/:subdomain/certificates, by status. Each
  # opens its own page, where a team admin compares the file with its dates and accepts
  # or declines it.
  @views [waiting: "Waiting", accepted: "Accepted", declined: "Declined"]

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.certificates?(team), do: raise(Web.Status.NotFound)
    {:ok, assign(socket, page_title: "Certificates")}
  end

  def handle_params(params, _uri, socket) do
    wanted = params["view"] || "waiting"
    view = @views |> Keyword.keys() |> Enum.find(&(Atom.to_string(&1) == wanted))
    if !view, do: raise(Web.Status.NotFound)
    team_id = socket.assigns.current_team.id
    counts = Certificate.count_by_status(team_id)

    socket
    |> assign(view: view, counts: counts, certificate_count: counts.waiting)
    |> assign(certificates: Certificate.get_all_for_team(team_id, view))
    |> then(&{:noreply, &1})
  end

  @doc "The Certificates page showing certificates in `status`."
  def view_path(team, :waiting), do: ~p"/teams/#{team}/certificates"
  def view_path(team, status), do: ~p"/teams/#{team}/certificates?#{[view: status]}"

  def render(assigns) do
    assigns = assign(assigns, views: @views)

    ~H"""
    <h1 class="title">Certificates</h1>
    <p class="lead measure">
      Members send a certificate. Accepting one records the award and attaches the certificate.
    </p>

    <.stat_switch id="certificates-switch" label="Certificates">
      <:view
        :for={{view, label} <- @views}
        id={"certificates-view-#{view}"}
        patch={view_path(@current_team, view)}
        current={@view == view}
        count={Map.fetch!(@counts, view)}
      >
        {label}
      </:view>
    </.stat_switch>

    <.empty_state
      :if={@certificates == []}
      id={"no-#{@view}-certificates"}
      title={empty_title(@view)}
    >
      {empty_text(@view)}
    </.empty_state>

    <p :if={@certificates != [] and @view == :waiting} class="hint mb-4">
      Open a certificate to check its qualification and dates, then accept or decline it.
    </p>

    <.table
      :if={@certificates != []}
      id={"#{@view}-certificates"}
      rows={@certificates}
      row_id={&"certificate-#{&1.id}"}
      class="table-stack"
    >
      <:col :let={certificate} label="Member" class="stack-title">{certificate.member.name}</:col>
      <:col :let={certificate} label="Qualification" class="stack-full">
        <.a navigate={~p"/teams/#{@current_team}/certificates/#{certificate.id}"}>{CertificateText.title(
          certificate
        )}</.a>
        <span
          :if={certificate.status == :waiting and is_nil(certificate.qualification_id)}
          class="hint block"
        >
          No qualification picked
        </span>
        <span :if={certificate.status == :declined} class="hint block">
          {certificate.decline_reason}
        </span>
      </:col>
      <:col :let={certificate} label="Dates" class="whitespace-nowrap">
        {CertificateText.dates(certificate)}
      </:col>
      <:col :let={certificate} label="Sent" class="whitespace-nowrap">
        {Format.date_short(certificate.inserted_at, @current_team.timezone)}
      </:col>
    </.table>
    """
  end

  defp empty_title(:waiting), do: "No certificates waiting"
  defp empty_title(:accepted), do: "No certificates accepted"
  defp empty_title(:declined), do: "No certificates declined"

  defp empty_text(:waiting),
    do: "Certificates members send show here for you to accept."

  defp empty_text(:accepted), do: "Certificates you accept show here, once they are sent."

  defp empty_text(:declined), do: "Certificates you decline show here, with the reason."
end
