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
  # An organization's start page, /o/<slug>, carries its brand until it has its own verify
  # host. A card from one of its teams carries it too, whichever page it was checked from.
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Check an ID card",
       scan_failed: false,
       client_ip: session["client_ip"]
     )}
  end

  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Organization.get_by_slug(slug) do
      %Organization{} = organization ->
        socket =
          socket
          |> assign(:form, to_form(%{"code" => ""}, as: "check"))
          |> assign(result: nil, organization: organization, start_path: ~p"/o/#{slug}")

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
      |> assign(result: result, organization: organization)
      |> assign(:start_path, if(organization, do: ~p"/o/#{organization.slug}", else: ~p"/"))

    {:noreply, socket}
  end

  def handle_event("check", %{"check" => %{"code" => input}}, socket),
    do: {:noreply, push_patch(socket, to: path_for(input))}

  def handle_event("scanned", %{"code" => input}, socket),
    do: {:noreply, push_patch(socket, to: path_for(input))}

  def handle_event("scan_failed", _params, socket) do
    {:noreply, assign(socket, :scan_failed, true)}
  end

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
      <h1 class="text-2xl font-semibold text-zinc-900">
        Check a search and rescue ID card
      </h1>
      <p :if={@organization} id="start-organization" class="mt-1 mb-0 text-zinc-900">
        For member teams of {@organization.name}.
      </p>
      <p class="mt-2 mb-0 text-zinc-600">
        Scan the QR code on the member's card. You'll see whether they're an active member
        of their team, with their photo.
      </p>

      <div id="scanner" phx-hook="QRScanner" phx-update="ignore" class="group mt-6 mb-6">
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
          <.button type="button" class="w-full justify-center" data-scan-stop>Stop</.button>
        </div>
      </div>
      <p :if={@scan_failed} id="scan-failed" class="text-danger-1">
        The camera didn't start. Allow camera access, or type the code.
      </p>

      <.form for={@form} id="check-form" phx-submit="check">
        <.input
          field={@form[:code]}
          label="Or type the code printed under the QR"
          placeholder="XXXX-XXXX"
          autocomplete="off"
          autocapitalize="characters"
          spellcheck="false"
          class="font-mono"
        />
        <.button size={:lg} class="w-full justify-center">Check</.button>
      </.form>

      <section class="mt-8 pt-6 border-t border-zinc-200 text-sm text-zinc-600">
        <h2 class="mb-2 font-semibold text-zinc-900">How it works</h2>
        <p class="mb-2">
          Each team keeps member records. SAR Duty checks the card against them, so a
          cancelled card, or a member who has left, shows here.
        </p>
        <p class="mb-0">
          A real card's QR code always opens <b class="text-zinc-900">{Web.VerifyHost.host()}</b>. Keep this page
          on your home screen if you check cards often.
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
        Check another card
      </.button>
    </div>
    """
  end

  defp result(%{result: %{status: :limited}} = assigns) do
    ~H"""
    <div id="result-limited">
      <.band kind={:bad} title="Too many tries">Wait a few minutes and try again</.band>
      <.panel>Too many codes from this connection didn't match a card.</.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :not_found}} = assigns) do
    ~H"""
    <div id="result-not-found">
      <.band kind={:bad} title="No card has this code">Check the code and try again</.band>
      <.panel>
        A card that doesn't check out here isn't valid. Codes are 8 letters and numbers,
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
          A real card's code only ever opens <b>{Web.VerifyHost.host()}</b>. Don't trust any
          page the card opened.
        </p>
      </.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :revoked}} = assigns) do
    ~H"""
    <div id="result-revoked">
      <.band kind={:bad} title="This card was cancelled">It isn't valid</.band>
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
      <.band :if={@status == :active} kind={:ok} title="Active member">Checked just now</.band>
      <.band :if={@status == :inactive} kind={:warn} title="Not an active member">
        {left_text(@member)}
      </.band>

      <.panel>
        <div class="flex items-center gap-4">
          <img
            id="result-photo"
            src={~p"/#{@result.card.code}/photo"}
            alt={"Photo of #{@member.name}"}
            class="size-28 shrink-0 rounded-lg border border-zinc-200 object-cover"
          />
          <h2 id="result-name" class="text-2xl font-semibold text-zinc-900">
            {@member.name}
          </h2>
        </div>

        <div class="flex items-center gap-3 mt-4 pt-4 border-t border-zinc-200">
          <img
            src={"#{Web.Endpoint.url()}/teams/#{@team.subdomain}/logo?shape=square"}
            alt=""
            class="size-14 shrink-0"
          />
          <div>
            <p id="result-team" class="mb-0 text-lg font-semibold leading-snug text-zinc-900">
              {@team.name}
            </p>
            <p :if={@team.organization} id="result-organization" class="mb-0 text-sm text-zinc-600">
              Member team of {@team.organization.name}
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
            <.fact label="Member" class="col-span-2">{member_years(@member, @team.timezone)}</.fact>
          <% end %>
        </div>

        <ul
          :if={@result.qualifications != []}
          id="result-qualifications"
          class="mt-4 pt-3 border-t border-zinc-200 text-sm"
        >
          <li :for={q <- @result.qualifications} class="flex justify-between gap-4 py-1">
            <span class="text-zinc-900">{q.name}</span>
            <span class="shrink-0 text-zinc-600">
              {BuildCardQualifications.status_text(q, @team.timezone)}
            </span>
          </li>
        </ul>
      </.panel>

      <p
        :if={@status == :active}
        id="result-check"
        class="mt-4 mb-0 p-4 rounded-lg border border-amber-200 bg-amber-50 text-sm text-amber-900"
      >
        <b>Match the photo to the person.</b>
        And check that the address bar says {Web.VerifyHost.host()}.
      </p>
      <p :if={@status == :inactive} class="mt-4 mb-0 text-zinc-900">
        This card doesn't qualify for member benefits.
      </p>
      <p class="mt-3 mb-0 text-sm text-zinc-500">
        From the team's records, last checked {last_checked(@team)}.
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
      @kind == :ok && "bg-success-1 text-success-content",
      @kind == :warn && "bg-warning-1 text-warning-content",
      @kind == :bad && "bg-danger-1 text-danger-content"
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
    <div class="mt-4 p-4 rounded-lg border border-zinc-200 bg-white">
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
      <div class="text-xs font-medium uppercase tracking-wide text-zinc-500">{@label}</div>
      <div class="text-lg font-semibold text-zinc-900">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp band_icon(:ok), do: "hero-check-circle"
  defp band_icon(:warn), do: "hero-exclamation-triangle"
  defp band_icon(:bad), do: "hero-x-circle"

  defp left_text(%{left_at: nil}), do: "Not a current member"

  defp left_text(member),
    do: "Left the team #{Service.Format.month_year(member.left_at, member.team.timezone)}"

  defp member_years(%{joined_at: joined_at, left_at: left_at}, timezone) do
    year = &(&1 |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%Y"))
    if left_at, do: "#{year.(joined_at)} – #{year.(left_at)}", else: "Since #{year.(joined_at)}"
  end

  defp last_checked(%{d4h_refreshed_at: nil}), do: "never"

  defp last_checked(team) do
    Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
  end
end
