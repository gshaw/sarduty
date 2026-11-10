defmodule Web.VerifyLive do
  use Web, :live_view_verify_layout

  import Web.Components.Scanner
  import Web.Components.Verify

  alias App.Model.DemoTeam
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Organization
  alias App.Model.PublishedPDF
  alias App.Operation.CheckMemberCard
  alias Service.Format
  alias Web.VerifyLimit

  # Public, on the verify site (Web.VerifyHost). A card's QR code opens /<code> here, and
  # so does a published PDF's verify code (#970): the length says which, 10 characters
  # for a card and 15 for a document. Scanning from this page is the careful check: it
  # takes the code out of the link and flags a link to any other site, which is what a
  # forged card would carry.
  #
  # A document shows what its definition's `verify shows` printed while it's current. One
  # replaced or withdrawn says so and shows nothing from the PDF. A tax credit letter's
  # reference number from before #970 is not found, as any unknown code: its letter was
  # printed again with an ID.
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
    sound = if result.status in [:active, :current], do: :ok, else: :error
    socket |> assign(sound_next: false) |> push_event("scan-sound", %{sound: sound})
  end

  defp scan_sound(socket, _result), do: socket

  # A card's or document's own page when the input names one, so the address bar shows
  # its code.
  defp path_for(input) do
    case read(input) do
      {:card, code} -> ~p"/#{MemberCard.format_code(code)}"
      {:document, code} -> ~p"/#{PublishedPDF.format_code(code)}"
      _other -> ~p"/?#{[code: input]}"
    end
  end

  # What the input names: `{:card, code}`, `{:document, code}`, `{:other_site, host}`
  # for a link anywhere else, or nil.
  defp read(input) do
    case MemberCard.code_from_scan(input, Web.VerifyHost.trusted_hosts()) do
      code when is_binary(code) ->
        {:card, code}

      {:other_site, host} ->
        {:other_site, host}

      nil ->
        input |> document_code() |> PublishedPDF.parse_code() |> then(&(&1 && {:document, &1}))
    end
  end

  defp document_code(input) do
    input = String.trim(input)

    case URI.parse(input) do
      %URI{scheme: scheme, path: path} when scheme in ["http", "https", "HTTP", "HTTPS"] ->
        case Regex.run(~r{^/([^/]+)/?$}, path || "") do
          [_path, code] -> code
          nil -> ""
        end

      _other ->
        input
    end
  end

  defp check("", _ip), do: nil

  defp check(input, ip) do
    cond do
      VerifyLimit.limited?(ip) -> %{status: :limited}
      match?({:document, _parsed}, read(input)) -> input |> read() |> elem(1) |> document(ip)
      true -> card(input, ip)
    end
  end

  defp card(input, ip) do
    result = look_up(input)

    cond do
      result[:sample] -> :ok
      result.status == :not_found -> VerifyLimit.miss(ip, result[:code])
      result[:card] -> VerifyLimit.hit(ip, result.card)
      true -> :ok
    end

    result
  end

  defp look_up(input) do
    case read(input) do
      {:other_site, host} -> %{status: :other_site, host: host, sample: false}
      {:card, code} -> CheckMemberCard.call(code)
      nil -> %{status: :not_found, sample: false}
    end
  end

  defp document(code, ip), do: code |> PublishedPDF.find_for_verify() |> document(ip, code)

  defp document(nil, ip, parsed) do
    VerifyLimit.miss(ip, parsed)
    %{status: :document_not_found, sample: false}
  end

  defp document(%PublishedPDF{} = pdf, ip, _parsed) do
    VerifyLimit.hit(ip, pdf)
    # A Try a demo team's: a visitor made it (#857).
    %{status: PublishedPDF.status(pdf), pdf: pdf, sample: DemoTeam.demo?(pdf.team_id)}
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
          placeholder="XXXXX-XXXXX"
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
        <p id="documents-note">
          A document a team published through SAR Duty, such as a tax credit letter, has a
          verify code too. Scan it, or type the 15 letters and numbers under it.
        </p>
        <p class="action">
          <.a id="samples-link" navigate={~p"/samples"}>Try a sample card</.a>
        </p>
      </section>
    </div>
    """
  end

  def render(%{result: %{pdf: _pdf}} = assigns) do
    ~H"""
    <.band
      :if={@result.sample}
      id="result-sample"
      kind={:info}
      title="Sample"
      class="mb-4"
    >
      Made up for demos. It is not a real team's, so never accept it.
    </.band>
    <.document_result result={@result} />
    <div class="mt-6">
      <.button id="check-another" navigate={@start_path} size={:lg} class="w-full">
        Verify another
      </.button>
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
        Codes are 10 letters and numbers, under the QR code. If the code is right, the card is
        not valid.
      </.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :document_not_found}} = assigns) do
    ~H"""
    <div id="result-not-found">
      <.band kind={:danger} title="No document has this code">Check the code and try again</.band>
      <.panel>
        The code is under the QR code on the document, 15 letters and numbers. If the code is
        right, the document is not one SAR Duty published.
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
        valid_until: MemberCard.valid_until(member.team),
        left: left_text(member, DateTime.utc_now())
      )

    ~H"""
    <div id={"result-#{@status}"}>
      <.band :if={@status == :active} kind={:success} title="Active member">Verified just now</.band>
      <.band :if={@status == :inactive} kind={:warning} title="Not an active member">{@left}</.band>

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

  # The definition's name, and the year it's for, if any: "Tax credit letter, 2026". The
  # PDF's own title is for files and emails; the team's name shows below it.
  defp document_heading(%PublishedPDF{name: name, year: year}) when is_integer(year),
    do: "#{name}, #{year}"

  defp document_heading(%PublishedPDF{name: name}), do: name

  defp document_result(%{result: %{status: :current, pdf: pdf}} = assigns) do
    assigns = assign(assigns, pdf: pdf, team: pdf.team)

    ~H"""
    <div id="result-current">
      <.band kind={:success} title={"Published by #{team_name(@team)}"}>
        Verified just now
      </.band>

      <.panel>
        <h2 id="result-title" class="heading mb-0">{document_heading(@pdf)}</h2>
        <p id="result-code" class="hint mono mb-0">{PublishedPDF.format_code(@pdf.code)}</p>

        <div class="card-section media">
          <img src={logo_src(@team, @result.sample)} alt="" class="logo-md" />
          <div>
            <p id="result-team" class="subheading mb-0">{team_name(@team)}</p>
            <p :if={@team.organization} id="result-organization" class="hint mb-0">
              {@team.organization.name}
            </p>
          </div>
        </div>

        <div class="mt-4">
          <.fact label="Published on">{Format.date_long(@pdf.inserted_at, @team.timezone)}</.fact>
        </div>

        <div :if={@pdf.shows != []} id="result-shows" class="card-section value-rows">
          <div :for={shown <- @pdf.shows}>
            <span>{shown["label"]}</span>
            <strong>{shown["text"]}</strong>
          </div>
        </div>
      </.panel>

      <p id="result-check" class="callout mt-4 text-sm">
        <b>Compare these with the paper.</b> If they are not the same, contact the team.
      </p>

      <.contact team={@team} />
    </div>
    """
  end

  defp document_result(%{result: %{status: :replaced, pdf: pdf}} = assigns) do
    assigns = assign(assigns, pdf: pdf, team: pdf.team)

    ~H"""
    <div id="result-replaced">
      <.band kind={:warning} title="Replaced">This is not the current one</.band>
      <.panel>
        <h2 id="result-name" class="heading mb-0">{@pdf.name}</h2>
        <p class="mt-2 mb-0">
          Replaced on {Format.date_long(@pdf.replaced_by.inserted_at, @team.timezone)}.
          Ask {team_name(@team)} for the current one.
        </p>
      </.panel>
    </div>
    """
  end

  defp document_result(%{result: %{status: :withdrawn, pdf: pdf}} = assigns) do
    assigns = assign(assigns, pdf: pdf, team: pdf.team)

    ~H"""
    <div id="result-withdrawn">
      <.band kind={:danger} title="Withdrawn">It is not valid</.band>
      <.panel>
        <h2 id="result-name" class="heading mb-0">{@pdf.name}</h2>
        <p class="mt-2 mb-0">
          Withdrawn by {team_name(@team)} on {Format.date_long(@pdf.withdrawn_at, @team.timezone)}.
        </p>
      </.panel>
    </div>
    """
  end

  defp team_name(team), do: team.legal_name || team.name

  attr :team, :map, required: true

  defp contact(assigns) do
    team = assigns.team

    lines =
      Enum.reject(
        [
          team.authorized_by_name,
          team.authorized_by_title,
          team.authorized_by_phone,
          team.authorized_by_email
        ],
        &(&1 in [nil, ""])
      )

    assigns = assign(assigns, :lines, lines)

    ~H"""
    <section :if={@lines != []} id="result-contact" class="small-print">
      <h2>Questions about this document</h2>
      <p>
        <%= for {line, index} <- Enum.with_index(@lines) do %>
          <br :if={index > 0} />{line}
        <% end %>
      </p>
    </section>
    """
  end

  # Coast Range SAR is only in the sample database, so the app has no logo for it.
  defp logo_src(_team, true = _sample), do: ~p"/images/sarduty-logo-square.png"

  defp logo_src(team, false),
    do: "#{Web.Endpoint.url()}/teams/#{team.subdomain}/logo?shape=square"

  defp expiry_text(%{ends_at: nil}, _timezone), do: "No expiry"

  defp expiry_text(%{ends_at: ends_at}, timezone),
    do: "Expires #{Service.Format.month_year(ends_at, timezone)}"

  # A member on their way out (Retiring) is still on the team, so the band says no more.
  defp left_text(member, now) do
    cond do
      Member.current?(member, now) ->
        nil

      member.left_at ->
        "Retired #{Service.Format.month_year(member.left_at, member.team.timezone)}"

      true ->
        "Retired"
    end
  end

  defp last_checked(%{d4h_refreshed_at: nil}), do: "never"

  defp last_checked(team) do
    Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
  end
end
