defmodule Web.VerifyLive do
  use Web, :live_view_verify_layout

  import Web.Components.Scanner
  import Web.Components.Verify

  alias App.Model.MemberCard
  alias App.Model.Organization
  alias App.Operation.CheckMemberCard
  alias Web.VerifyLimit

  # Public, on the verify site (Web.VerifyHost). A card's QR code opens /<code> here.
  # Scanning from this page is the careful check: it takes the code out of a card's link
  # and flags a link to any other site, which is what a forged card would carry.
  #
  # Misses count toward a per-IP limit (Web.VerifyLimit). It's checked here rather than in
  # a plug, which would miss checks sent over the open connection. A bad link opened
  # directly counts twice, once for the HTTP render and once on connect.
  #
  # An organization's scan page, /orgs/<slug>, carries its brand until it has its own verify
  # host. A card's result keeps the team's brand, with the organization's name under it.
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Verify a search and rescue ID card",
       scan_failed: false,
       sound_next: false,
       scanned: false,
       client_ip: session["client_ip"]
     )}
  end

  # ?scan=1 opens the camera: Verify another card after a scan comes back scanning.
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    case Organization.get_by_slug(slug) do
      %Organization{} = organization ->
        socket =
          socket
          |> assign(:autostart, params["scan"] == "1")
          |> assign(:form, to_form(%{"code" => ""}, as: "check"))
          |> assign(result: nil, organization: organization, start_path: ~p"/orgs/#{slug}")

        {:noreply, socket}

      nil ->
        {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_params(params, _uri, socket) do
    input = params["code"] || ""
    result = check(input, socket.assigns.client_ip)
    organization = result_organization(result)

    socket =
      socket
      |> assign(:form, to_form(%{"code" => input}, as: "check"))
      |> assign(result: result, organization: nil, autostart: params["scan"] == "1")
      |> assign(:start_path, if(organization, do: ~p"/orgs/#{organization}", else: ~p"/"))
      |> scan_sound(result)

    {:noreply, socket}
  end

  def handle_event("check", %{"check" => %{"code" => input}}, socket),
    do:
      {:noreply,
       socket |> assign(sound_next: true, scanned: false) |> push_patch(to: path_for(input))}

  def handle_event("scanned", %{"code" => input}, socket),
    do:
      {:noreply,
       socket |> assign(sound_next: true, scanned: true) |> push_patch(to: path_for(input))}

  def handle_event("scan_failed", _params, socket) do
    {:noreply, assign(socket, :scan_failed, true)}
  end

  # A scan or a typed code sounds its result. A card's link opened directly stays quiet,
  # since a browser plays nothing before a tap.
  defp scan_sound(%{assigns: %{sound_next: true}} = socket, result) when result != nil do
    sound = if result.status == :active, do: :ok, else: :error
    socket |> assign(sound_next: false) |> push_event("scan-sound", %{sound: sound})
  end

  defp scan_sound(socket, _result), do: socket

  # A card's own page when the input names one, so the address bar shows its code.
  defp path_for(input) do
    case MemberCard.code_from_scan(input, Web.VerifyHost.trusted_hosts()) do
      code when is_binary(code) -> ~p"/#{MemberCard.format_code(code)}"
      _ -> ~p"/?#{[code: input]}"
    end
  end

  defp check("", _ip), do: nil

  defp check(input, ip) do
    if VerifyLimit.limited?(ip) do
      %{status: :limited}
    else
      result = look_up(input)
      if result.status == :not_found and not result.sample, do: VerifyLimit.miss(ip)
      result
    end
  end

  defp look_up(input) do
    case MemberCard.code_from_scan(input, Web.VerifyHost.trusted_hosts()) do
      {:other_site, host} -> %{status: :other_site, host: host, sample: false}
      nil -> %{status: :not_found, sample: false}
      code -> CheckMemberCard.call(code)
    end
  end

  defp result_organization(%{card: %MemberCard{member: %{team: team}}}), do: team.organization
  defp result_organization(_result), do: nil

  def render(%{result: nil} = assigns) do
    ~H"""
    <div id="start">
      <h1 class="heading">
        Verify a search and rescue ID card
      </h1>
      <p class="text-text-muted">
        Scan the QR code on the member's ID card. SAR Duty shows whether they are an active
        member of their team, with their photo.
      </p>

      <.qr_scanner label="Scan a card" class="mb-6" data-autostart={@autostart} />
      <p :if={@scan_failed} id="scan-failed" class="text-danger-text">
        The camera did not start. Allow camera access, or type the code.
      </p>

      <.form for={@form} id="check-form" phx-submit="check">
        <.input
          field={@form[:code]}
          label="Or type the code under the QR code"
          placeholder="XXXX-XXXX"
          autocomplete="off"
          autocapitalize="characters"
          spellcheck="false"
          class="font-mono"
        />
        <.button size={:lg} class="w-full">Verify card</.button>
      </.form>

      <section class="small-print">
        <h2>How it works</h2>
        <p>
          SAR Duty verifies each card against the team's D4H records. A cancelled card shows
          here, and so does a retired member.
        </p>
        <p>
          A real card's QR code always opens <b class="text-text">{Web.VerifyHost.host()}</b>. Add this page
          to your home screen if you verify ID cards often.
        </p>
        <p class="action">
          <.a id="samples-link" navigate={~p"/samples"}>Try a sample card</.a>
        </p>
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.band
      :if={@result[:sample]}
      id="result-sample"
      kind={:info}
      title="Sample card"
      class="mb-4"
    >
      Made up for demos. It is not a real member, so never accept it as ID.
    </.band>
    <.result result={@result} />
    <div class="mt-6">
      <.button
        id="check-another"
        navigate={another_path(@start_path, @scanned)}
        size={:lg}
        class="w-full"
      >
        Verify another card
      </.button>
    </div>
    """
  end

  # After a scan, the camera opens again for the next card.
  defp another_path(start_path, true = _scanned), do: start_path <> "?scan=1"
  defp another_path(start_path, false), do: start_path

  defp result(%{result: %{status: :limited}} = assigns) do
    ~H"""
    <div id="result-limited">
      <.band kind={:danger} title="Too many tries">Wait a few minutes and try again</.band>
      <.panel>Too many codes from this connection did not match a card.</.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :not_found}} = assigns) do
    ~H"""
    <div id="result-not-found">
      <.band kind={:danger} title="No card has this code">Check the code and try again</.band>
      <.panel>
        Codes are 8 letters and numbers, under the QR code. If the code is right, the card is
        not valid.
      </.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :other_site}} = assigns) do
    ~H"""
    <div id="result-other-site">
      <.band kind={:danger} title="Not a SAR Duty card">Do not accept this card</.band>
      <.panel>
        <p>
          Its QR code links to <span class="font-mono text-danger-text">{@result.host}</span>.
        </p>
        <p>
          A real card's QR code always opens <b>{Web.VerifyHost.host()}</b>. Do not trust any
          page this card opened.
        </p>
      </.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :revoked}} = assigns) do
    ~H"""
    <div id="result-revoked">
      <.band kind={:danger} title="This card was cancelled">It is not valid</.band>
      <.panel>The team replaced or withdrew this card.</.panel>
    </div>
    """
  end

  defp result(%{result: %{status: status, card: card}} = assigns) do
    member = card.member

    assigns =
      assign(assigns,
        member: member,
        team: member.team,
        status: status,
        valid_until: MemberCard.valid_until(member.team)
      )

    ~H"""
    <div id={"result-#{@status}"}>
      <.band :if={@status == :active} kind={:success} title="Active member">Verified just now</.band>
      <.band :if={@status == :inactive} kind={:warning} title="Not an active member">
        {left_text(@member)}
      </.band>

      <.panel>
        <%!-- No photo for a retired member: "not active" needs none (#176). --%>
        <div class="media">
          <img
            :if={@status == :active}
            id="result-photo"
            src={~p"/#{@result.card.code}/photo"}
            alt={"Photo of #{@member.name}"}
            class="photo photo-sm"
          />
          <h2 id="result-name" class="heading mb-0">{@member.name}</h2>
        </div>

        <div class="card-section media">
          <img
            src={logo_src(@team, @result.sample)}
            alt=""
            class="logo-md"
          />
          <div>
            <p id="result-team" class="subheading mb-0">{@team.name}</p>
            <p :if={@team.organization} id="result-organization" class="hint mb-0">
              {@team.organization.name}
            </p>
          </div>
        </div>

        <%!-- The same three columns as the front of the Apple pass. --%>
        <div id="result-facts" class="grid grid-cols-3 gap-2 mt-4">
          <%= if @status == :active do %>
            <.fact label="Status">Active</.fact>
            <.fact :if={@member.joined_at} label="Member since">
              {Service.Format.month_year(@member.joined_at, @team.timezone)}
            </.fact>
            <.fact :if={@valid_until} label="Valid until" class="text-right">
              {Service.Format.month_year(@valid_until, @team.timezone)}
            </.fact>
          <% else %>
            <.fact label="Status">Not active</.fact>
          <% end %>
        </div>

        <ul
          :if={@result.qualifications != []}
          id="result-qualifications"
          class="card-section value-rows text-sm"
        >
          <li :for={q <- @result.qualifications}>
            <span>{q.name}</span>
            <span class="text-text-muted">{expiry_text(q, @team.timezone)}</span>
          </li>
        </ul>
      </.panel>

      <p :if={@status == :active} id="result-check" class="callout mt-4 text-sm">
        <b>Compare the photo with the person.</b>
        Make sure the address bar shows {Web.VerifyHost.host()}.
      </p>
      <p :if={@status == :inactive} class="mt-4">
        This card does not qualify for member benefits.
      </p>
      <p class="hint">
        From the team's D4H records, last refreshed {last_checked(@team)}.
      </p>
    </div>
    """
  end

  # Coast Range SAR is only in the sample database, so the app has no logo for it.
  defp logo_src(_team, true = _sample), do: ~p"/images/sarduty-logo-square.png"

  defp logo_src(team, false),
    do: "#{Web.Endpoint.url()}/teams/#{team.subdomain}/logo?shape=square"

  defp expiry_text(%{ends_at: nil}, _timezone), do: "No expiry"

  defp expiry_text(%{ends_at: ends_at}, timezone),
    do: "Expires #{Service.Format.month_year(ends_at, timezone)}"

  defp left_text(%{left_at: nil}), do: "Retired"

  defp left_text(member),
    do: "Retired #{Service.Format.month_year(member.left_at, member.team.timezone)}"

  defp last_checked(%{d4h_refreshed_at: nil}), do: "never"

  defp last_checked(team) do
    Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
  end
end
