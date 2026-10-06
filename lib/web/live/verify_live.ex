defmodule Web.VerifyLive do
  use Web, :live_view_verify_layout

  alias App.Model.MemberCard
  alias App.Model.Organization
  alias App.Operation.BuildCardQualifications
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
       page_title: "Verify an ID card",
       scan_failed: false,
       sound_next: false,
       client_ip: session["client_ip"]
     )}
  end

  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Organization.get_by_slug(slug) do
      %Organization{} = organization ->
        socket =
          socket
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
      |> assign(result: result, organization: nil)
      |> assign(:start_path, if(organization, do: ~p"/orgs/#{organization}", else: ~p"/"))
      |> scan_sound(result)

    {:noreply, socket}
  end

  def handle_event("check", %{"check" => %{"code" => input}}, socket),
    do: {:noreply, socket |> assign(sound_next: true) |> push_patch(to: path_for(input))}

  def handle_event("scanned", %{"code" => input}, socket),
    do: {:noreply, socket |> assign(sound_next: true) |> push_patch(to: path_for(input))}

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
      if result.status == :not_found, do: VerifyLimit.miss(ip)
      result
    end
  end

  defp look_up(input) do
    with code when is_binary(code) <-
           MemberCard.code_from_scan(input, Web.VerifyHost.trusted_hosts()),
         %MemberCard{} = card <- MemberCard.find_by_code(code) do
      now = DateTime.utc_now()
      status = MemberCard.status(card, now)
      %{status: status, card: card, qualifications: qualifications(status, card, now)}
    else
      {:other_site, host} -> %{status: :other_site, host: host}
      _ -> %{status: :not_found}
    end
  end

  defp result_organization(%{card: %MemberCard{member: %{team: team}}}), do: team.organization
  defp result_organization(_result), do: nil

  defp qualifications(:active, %MemberCard{member: member}, now),
    do: BuildCardQualifications.call(member.team, member, now)

  defp qualifications(_status, _card, _now), do: []

  def render(%{result: nil} = assigns) do
    ~H"""
    <div id="start">
      <h1 class="text-2xl font-semibold text-base-content">
        Verify a search and rescue ID card
      </h1>
      <p class="mt-2 mb-0 text-secondary-1">
        Scan the QR code on the member's ID card. You'll see whether they're an active member
        of their team, with their photo.
      </p>

      <div id="scanner" phx-hook="QRScanner" phx-update="ignore" class="mt-6 mb-6">
        <div data-scan-state class="group">
          <video class="hidden group-data-scanning:block w-full rounded" playsinline muted></video>
          <div class="group-data-scanning:hidden">
            <.button
              type="button"
              variant={:primary}
              size={:lg}
              class="w-full justify-center"
              data-scan-start
            >
              Scan a card
            </.button>
          </div>
          <div class="hidden group-data-scanning:block mt-2">
            <.button type="button" class="w-full justify-center" data-scan-stop>Stop scanning</.button>
          </div>
        </div>
        <.switch
          id="sound-switch"
          label="Sound"
          compact
          class="mt-2"
          checked
          phx-hook="SoundSwitch"
          phx-update="ignore"
        />
      </div>
      <p :if={@scan_failed} id="scan-failed" class="text-danger-1">
        The camera did not start. Allow camera access, or type the code.
      </p>

      <.form for={@form} id="check-form" phx-submit="check">
        <.input
          field={@form[:code]}
          label="Or type the code printed under the QR code"
          placeholder="XXXX-XXXX"
          autocomplete="off"
          autocapitalize="characters"
          spellcheck="false"
          class="font-mono"
        />
        <.button size={:lg} class="w-full justify-center">Verify card</.button>
      </.form>

      <section class="mt-8 pt-6 border-t border-hr text-sm text-secondary-1">
        <h2 class="mb-2 font-semibold text-base-content">How it works</h2>
        <p class="mb-2">
          Each team keeps member records. SAR Duty verifies the card against them, so a
          cancelled card, or a member who has left, shows here.
        </p>
        <p class="mb-0">
          A real card's QR code always opens <b class="text-base-content">{Web.VerifyHost.host()}</b>. Keep this page
          on your home screen if you verify ID cards often.
        </p>
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.result result={@result} />
    <div class="mt-6">
      <.button id="check-another" navigate={@start_path} size={:lg} class="w-full justify-center">
        Verify another card
      </.button>
    </div>
    """
  end

  defp result(%{result: %{status: :limited}} = assigns) do
    ~H"""
    <div id="result-limited">
      <.band kind={:bad} title="Too many tries">Wait a few minutes and try again</.band>
      <.panel>Too many codes from this connection did not match a card.</.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :not_found}} = assigns) do
    ~H"""
    <div id="result-not-found">
      <.band kind={:bad} title="No card has this code">Check the code and try again</.band>
      <.panel>
        A card that SAR Duty cannot verify here is not valid. Codes are 8 letters and numbers,
        printed under the QR code.
      </.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :other_site}} = assigns) do
    ~H"""
    <div id="result-other-site">
      <.band kind={:bad} title="Not a SAR Duty card">Treat this card as forged</.band>
      <.panel>
        <p>
          Its QR code links to <span class="font-mono text-danger-1">{@result.host}</span>.
        </p>
        <p class="mt-2">
          A real card's code only ever opens <b>{Web.VerifyHost.host()}</b>. Do not trust any
          page the card opened.
        </p>
      </.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :revoked}} = assigns) do
    ~H"""
    <div id="result-revoked">
      <.band kind={:bad} title="This card was cancelled">It is not valid</.band>
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
      <.band :if={@status == :active} kind={:ok} title="Active member">Verified just now</.band>
      <.band :if={@status == :inactive} kind={:warn} title="Not an active member">
        {left_text(@member)}
      </.band>

      <.panel>
        <%!-- No photo for someone who has left: "not active" needs none (#176). --%>
        <div class="flex items-center gap-4">
          <img
            :if={@status == :active}
            id="result-photo"
            src={~p"/#{@result.card.code}/photo"}
            alt={"Photo of #{@member.name}"}
            class="size-28 shrink-0 rounded-lg border border-hr object-cover"
          />
          <h2 id="result-name" class="text-2xl font-semibold text-base-content">
            {@member.name}
          </h2>
        </div>

        <div class="flex items-center gap-3 mt-4 pt-4 border-t border-hr">
          <img
            src={"#{Web.Endpoint.url()}/teams/#{@team.subdomain}/logo?shape=square"}
            alt=""
            class="size-14 shrink-0"
          />
          <div>
            <p id="result-team" class="mb-0 text-lg font-semibold leading-snug text-base-content">
              {@team.name}
            </p>
            <p :if={@team.organization} id="result-organization" class="mb-0 text-sm text-secondary-1">
              {@team.organization.name}
            </p>
          </div>
        </div>

        <%!-- The same three columns as the front of the Apple pass. --%>
        <div id="result-facts" class="grid grid-cols-3 gap-2 mt-4">
          <%= if @status == :active do %>
            <.fact label="Status">Active</.fact>
            <.fact label="Member since">
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
          class="mt-4 pt-3 border-t border-hr text-sm"
        >
          <li :for={q <- @result.qualifications} class="flex justify-between gap-4 py-1">
            <span class="text-base-content">{q.name}</span>
            <span class="shrink-0 text-secondary-1">
              {BuildCardQualifications.status_text(q, @team.timezone)}
            </span>
          </li>
        </ul>
      </.panel>

      <p
        :if={@status == :active}
        id="result-check"
        class="callout mt-4 mb-0 text-sm"
      >
        <b>Match the photo to the person.</b>
        And check that the address bar says {Web.VerifyHost.host()}.
      </p>
      <p :if={@status == :inactive} class="mt-4 mb-0 text-base-content">
        This card does not qualify for member benefits.
      </p>
      <p class="mt-3 mb-0 text-sm text-secondary-1">
        From the team's D4H records, last refreshed {last_checked(@team)}.
      </p>
    </div>
    """
  end

  attr :kind, :atom, required: true, values: [:ok, :warn, :bad]
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp band(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 p-4 rounded-lg",
      @kind == :ok && "bg-(--success) text-(--on-fill)",
      @kind == :warn && "bg-(--warning) text-(--on-warning)",
      @kind == :bad && "bg-(--danger) text-(--on-fill)"
    ]}>
      <.icon name={band_icon(@kind)} class="size-8 shrink-0" />
      <div>
        <div class="text-xl font-semibold">{@title}</div>
        <div class="text-sm">{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <div class="mt-4 p-4 rounded-lg border border-hr bg-base-0">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <div class={@class}>
      <div class="text-xs font-medium uppercase tracking-wide text-secondary-1">{@label}</div>
      <div class="text-lg font-semibold text-base-content">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp band_icon(:ok), do: "hero-check-circle"
  defp band_icon(:warn), do: "hero-exclamation-triangle"
  defp band_icon(:bad), do: "hero-x-circle"

  defp left_text(%{left_at: nil}), do: "Not a current member"

  defp left_text(member),
    do: "Left the team #{Service.Format.month_year(member.left_at, member.team.timezone)}"

  defp last_checked(%{d4h_refreshed_at: nil}), do: "never"

  defp last_checked(team) do
    Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
  end
end
