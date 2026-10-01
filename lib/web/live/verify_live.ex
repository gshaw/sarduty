defmodule Web.VerifyLive do
  use Web, :live_view_verify_layout

  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications
  alias Web.VerifyLimit

  # Public, on the verify site (Web.VerifyHost). A card's QR code opens /<code> here.
  # Scanning from this page is the careful check: it takes the code out of a card's link
  # and flags a link to any other site, which is what a forged card would carry.
  #
  # Misses count toward a per-IP limit (Web.VerifyLimit). It's checked here rather than in
  # a plug, which would miss checks sent over the open connection. A bad link opened
  # directly counts twice, once for the HTTP render and once on connect.
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Check an ID card",
       scan_failed: false,
       client_ip: session["client_ip"]
     )}
  end

  def handle_params(params, _uri, socket) do
    input = params["code"] || ""

    socket =
      socket
      |> assign(:form, to_form(%{"code" => input}, as: "check"))
      |> assign(:result, check(input, socket.assigns.client_ip))

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

  defp qualifications(:active, %MemberCard{member: member}, now),
    do: BuildCardQualifications.call(member.team, member, now)

  defp qualifications(_status, _card, _now), do: []

  def render(%{result: nil} = assigns) do
    ~H"""
    <div id="start" class="px-4 pt-6">
      <h1 class="text-3xl font-bold leading-tight">Check a search and rescue ID card</h1>
      <p class="mt-2 text-lg text-base-content/70">
        Scan the QR code on the member's card. You'll see whether they're an active member
        of their team, with their photo.
      </p>

      <div id="scanner" phx-hook="QRScanner" phx-update="ignore" class="group mt-6">
        <video class="hidden group-data-scanning:block w-full rounded-xl" playsinline muted></video>
        <div class="group-data-scanning:hidden">
          <.button
            type="button"
            variant={:primary}
            size={:lg}
            class="w-full justify-center text-center"
            data-scan-start
          >
            Scan a card
          </.button>
        </div>
        <div class="hidden group-data-scanning:block mt-2">
          <.button type="button" class="w-full justify-center text-center" data-scan-stop>Stop</.button>
        </div>
      </div>
      <p :if={@scan_failed} id="scan-failed" class="mt-2 text-danger-1">
        The camera didn't start. Allow camera access, or type the code.
      </p>

      <.form for={@form} id="check-form" phx-submit="check" class="mt-6">
        <label for="check_code" class="block text-center text-base-content/70">
          or type the code printed under the QR
        </label>
        <div class="mt-2 flex gap-2">
          <input
            type="text"
            id="check_code"
            name={@form[:code].name}
            value={@form[:code].value}
            placeholder="XXXX-XXXX"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
            class="min-w-0 flex-1 rounded-xl border border-zinc-300 bg-white px-3 py-3 font-mono text-xl tracking-wider"
          />
          <.button size={:lg}>Check</.button>
        </div>
      </.form>

      <section class="mt-8 border-t border-zinc-300 pt-5 text-base-content/80">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
          How it works
        </h2>
        <p class="mt-2">
          Each team keeps its records in D4H. SAR Duty checks the card against them, so a
          cancelled card, or a member who has left, shows here.
        </p>
        <p class="mt-2">
          A real card's QR code always opens <b>{Web.VerifyHost.host()}</b>. Keep this page
          on your home screen if you check cards often.
        </p>
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.result result={@result} />
    <div class="px-4 mt-5">
      <.button
        id="check-another"
        navigate={~p"/"}
        size={:lg}
        class="w-full justify-center text-center"
      >
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
          Its QR code links to <span class="rounded bg-red-50 px-1.5 font-mono text-red-800">{@result.host}</span>.
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

      <div class="mx-4 mt-4 rounded-2xl bg-white p-4 shadow-sm">
        <div class="flex items-center gap-4">
          <img
            id="result-photo"
            src={~p"/#{@result.card.code}/photo"}
            alt={"Photo of #{@member.name}"}
            class="size-32 shrink-0 rounded-xl border border-zinc-300 object-cover"
          />
          <p id="result-name" class="text-2xl font-bold leading-tight">{@member.name}</p>
        </div>

        <div class="mt-4 flex items-center gap-3 border-t border-zinc-200 pt-4">
          <img
            src={"#{Web.Endpoint.url()}/teams/#{@team.subdomain}/logo"}
            alt=""
            class="size-11 shrink-0"
          />
          <p id="result-team" class="font-semibold">{@team.name}</p>
        </div>

        <div class="mt-4 grid grid-cols-2 gap-3">
          <%= if @status == :active do %>
            <.fact label="Member since">
              {Service.Format.month_year(@member.joined_at, @team.timezone)}
            </.fact>
            <.fact :if={@valid_until} label="Card valid until">
              {Service.Format.month_year(@valid_until, @team.timezone)}
            </.fact>
          <% else %>
            <.fact label="Member">{member_years(@member, @team.timezone)}</.fact>
          <% end %>
        </div>

        <ul
          :if={@result.qualifications != []}
          id="result-qualifications"
          class="mt-4 border-t border-zinc-200 pt-3"
        >
          <li :for={q <- @result.qualifications} class="flex justify-between py-1">
            <span>{q.name}</span>
            <span class={[
              "font-semibold",
              if(q.status == :not_current, do: "text-danger-1", else: "text-success-1")
            ]}>
              {BuildCardQualifications.status_text(q, @team.timezone)}
            </span>
          </li>
        </ul>
      </div>

      <div
        :if={@status == :active}
        id="result-check"
        class="mx-4 mt-4 rounded-2xl border border-amber-300 bg-amber-50 p-3"
      >
        <b>Match the photo to the person.</b>
        And check that the address bar says {Web.VerifyHost.host()}.
      </div>
      <p :if={@status == :inactive} class="mx-4 mt-4">
        This card doesn't qualify for member benefits.
      </p>
      <p class="mx-4 mt-3 text-sm text-base-content/60">
        From the team's D4H records, last checked {last_checked(@team)}.
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
      "flex items-center gap-3 px-4 py-4 text-white",
      @kind == :ok && "bg-green-700",
      @kind == :warn && "bg-amber-700",
      @kind == :bad && "bg-red-700"
    ]}>
      <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-white/20 text-2xl font-bold">
        {band_icon(@kind)}
      </span>
      <div>
        <div class="text-2xl font-extrabold leading-tight">{@title}</div>
        <div class="text-sm opacity-90">{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <div class="mx-4 mt-4 rounded-2xl bg-white p-4 text-lg shadow-sm">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <div>
      <div class="text-xs uppercase tracking-wide text-base-content/60">{@label}</div>
      <div class="text-lg font-semibold">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp band_icon(:ok), do: "✓"
  defp band_icon(:warn), do: "!"
  defp band_icon(:bad), do: "✕"

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
