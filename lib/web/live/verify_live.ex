defmodule Web.VerifyLive do
  use Web, :live_view_narrow_layout

  alias App.Model.MemberCard

  # Public: whoever is checking a card opens this page on their own phone, so a forged
  # card can't send them to a look-alike site.
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
    {:noreply, push_patch(socket, to: ~p"/verify?#{[code: input]}")}
  end

  def handle_event("scan_failed", _params, socket) do
    {:noreply, assign(socket, :scan_failed, true)}
  end

  defp check(""), do: nil

  defp check(input) do
    with code when is_binary(code) <- MemberCard.normalize_code(input),
         %MemberCard{} = card <- MemberCard.find_by_code(code) do
      %{status: MemberCard.status(card, DateTime.utc_now()), card: card}
    else
      _ -> %{status: :not_found}
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="heading">Check an ID card</h1>
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

    <.result :if={@result} result={@result} />
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
      <div class="flex gap-4 items-start">
        <img
          src={~p"/verify/#{@result.card.code}/photo"}
          alt={"Photo of #{@member.name}"}
          class="w-28 rounded"
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
      <.hint>
        Make sure the photo matches the person. Status is from the team's D4H records, last
        checked {last_checked(@team)}.
      </.hint>
    </div>
    """
  end

  defp last_checked(%{d4h_refreshed_at: nil}), do: "never"

  defp last_checked(team) do
    Service.Format.datetime_short(team.d4h_refreshed_at, team.timezone)
  end
end
