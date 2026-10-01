defmodule Web.VerifyLive do
  use Web, :live_view_narrow_layout

  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications

  # Public. A card's QR code opens /verify/:code here. Scanning from this page is the
  # careful check: it takes the code out of a link to this site and flags a link to any
  # other, which is what a forged card would carry.
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Check an ID card", scan_failed: false)}
  end

  def handle_params(params, _uri, socket) do
    input = params["code"] || ""

    socket =
      socket
      |> assign(:form, to_form(%{"code" => input}, as: "check"))
      |> assign(:result, check(input))

    {:noreply, socket}
  end

  def handle_event("check", %{"check" => %{"code" => input}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/verify?#{[code: input]}")}
  end

  def handle_event("scanned", %{"code" => input}, socket) do
    case MemberCard.code_from_scan(input, Web.Endpoint.host()) do
      code when is_binary(code) ->
        {:noreply, push_patch(socket, to: ~p"/verify/#{MemberCard.format_code(code)}")}

      _ ->
        {:noreply, push_patch(socket, to: ~p"/verify?#{[code: input]}")}
    end
  end

  def handle_event("scan_failed", _params, socket) do
    {:noreply, assign(socket, :scan_failed, true)}
  end

  defp check(""), do: nil

  defp check(input) do
    with code when is_binary(code) <- MemberCard.code_from_scan(input, Web.Endpoint.host()),
         %MemberCard{} = card <- MemberCard.find_by_code(code) do
      now = DateTime.utc_now()
      status = MemberCard.status(card, now)
      %{status: status, card: card, qualifications: qualifications(status, card, now)}
    else
      {:other_site, host} -> %{status: :other_site, host: host}
      _ -> %{status: :not_found}
    end
  end

  defp qualifications(:revoked, _card, _now), do: []

  defp qualifications(_status, %MemberCard{member: member}, now),
    do: BuildCardQualifications.call(member.team, member, now)

  def render(assigns) do
    ~H"""
    <h1 class="heading">Check an ID card</h1>
    <%!-- First, so a phone that opened a card's link sees it without scrolling. --%>
    <.result :if={@result} result={@result} />
    <p>Scan the QR code on the member's card, or type the code printed under it.</p>

    <div id="scanner" phx-hook="QRScanner" phx-update="ignore" class="group my-p">
      <video class="hidden group-data-scanning:block w-full rounded" playsinline muted></video>
      <div class="group-data-scanning:hidden">
        <.button type="button" data-scan-start>Scan a card</.button>
      </div>
      <div class="hidden group-data-scanning:block mt-2">
        <.button type="button" data-scan-stop>Stop</.button>
      </div>
    </div>
    <p :if={@scan_failed} id="scan-failed" class="text-danger-1">
      The camera didn't start. Allow camera access, or type the code.
    </p>

    <.form for={@form} id="check-form" phx-submit="check">
      <.input
        field={@form[:code]}
        label="Code"
        autocomplete="off"
        autocapitalize="characters"
        spellcheck="false"
      />
      <.form_actions>
        <.button variant={:primary}>Check</.button>
      </.form_actions>
    </.form>
    """
  end

  defp result(%{result: %{status: :not_found}} = assigns) do
    ~H"""
    <div id="result-not-found" class="my-p">
      <p class="heading text-danger-1">No card has this code</p>
      <p>Check the code and try again. A card that doesn't check out here isn't valid.</p>
    </div>
    """
  end

  defp result(%{result: %{status: :other_site}} = assigns) do
    ~H"""
    <div id="result-other-site" class="my-p">
      <p class="heading text-danger-1">This QR code isn't from SAR Duty</p>
      <p>
        It links to <span class="font-mono">{@result.host}</span>. A real card's code opens {Web.Endpoint.host()}. Treat the card as forged.
      </p>
    </div>
    """
  end

  defp result(%{result: %{status: :revoked}} = assigns) do
    ~H"""
    <div id="result-revoked" class="my-p">
      <p class="heading text-danger-1">This card was cancelled</p>
      <p>The team replaced or withdrew it. It isn't valid.</p>
    </div>
    """
  end

  defp result(%{result: %{status: status, card: card}} = assigns) do
    assigns = assign(assigns, member: card.member, team: card.member.team, status: status)

    ~H"""
    <div id={"result-#{@status}"} class="my-p">
      <p :if={@status == :active} class="heading text-success-1">Active member</p>
      <p :if={@status == :inactive} class="heading text-danger-1">Not an active member</p>
      <div class="flex flex-wrap gap-4 items-start">
        <img
          id="result-photo"
          src={~p"/verify/#{@result.card.code}/photo"}
          alt={"Photo of #{@member.name}"}
          class="w-48 rounded"
        />
        <dl>
          <dt>Name</dt>
          <dd id="result-name">{@member.name}</dd>
          <dt>Team</dt>
          <dd>{@team.name}</dd>
          <dt>Member since</dt>
          <dd>
            {Service.Format.date_long(@member.joined_at, @team.timezone)} · {Service.Format.months_or_years_ago(
              @member.joined_at
            )}
          </dd>
        </dl>
      </div>
      <p :if={@result.qualifications != []} class="font-bold mt-p">Qualifications</p>
      <ul :if={@result.qualifications != []} id="result-qualifications">
        <li :for={q <- @result.qualifications} class={q.status == :not_current && "text-danger-1"}>
          {BuildCardQualifications.describe(q, @team.timezone)}
        </li>
      </ul>
      <p id="result-check" class="font-bold mt-p">
        Make sure the photo matches the person, and that the address bar says {Web.Endpoint.host()}.
      </p>
      <.hint>
        Status is from the team's D4H records, last checked {last_checked(@team)}.
      </.hint>
    </div>
    """
  end

  defp last_checked(%{d4h_refreshed_at: nil}), do: "never"

  defp last_checked(team) do
    Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
  end
end
