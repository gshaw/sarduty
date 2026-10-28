defmodule Web.VerifyLetterLive do
  use Web, :live_view_verify_layout

  import Web.Components.Verify

  alias App.Model.TaxCreditLetter
  alias Service.Format
  alias Web.VerifyLimit

  # Public, on the verify site (Web.VerifyHost), beside the ID card check. A letter's QR
  # code opens /letters/<reference number>. It shows the hours the team issued, so a
  # reader can compare them with the paper. Only a team's current letter verifies: one it
  # replaced or deleted is not found. An old reference number (before #207) was easy to
  # guess, so it shows nothing until the reader also gives the member's last name.
  # Misses share the ID card check's per-IP limit.
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Verify a tax credit letter",
       client_ip: session["client_ip"]
     )}
  end

  def handle_params(%{"ref" => input}, _uri, socket) do
    result =
      case TaxCreditLetter.parse_ref_id(input) do
        {:old, ref_id} -> %{status: :needs_last_name, ref_id: ref_id}
        parsed -> check(socket.assigns.client_ip, fn -> look_up(parsed) end)
      end

    {:noreply, assign_result(socket, result, input)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, assign_result(socket, nil, "")}

  def handle_event("check", %{"check" => %{"ref" => input}}, socket) do
    case TaxCreditLetter.parse_ref_id(input) do
      {_kind, ref_id} ->
        {:noreply, push_patch(socket, to: ~p"/letters/#{ref_id}")}

      nil ->
        result = check(socket.assigns.client_ip, fn -> %{status: :not_found} end)
        {:noreply, assign_result(socket, result, input)}
    end
  end

  def handle_event("check_name", %{"check" => %{"last_name" => last_name}}, socket) do
    parsed = {:old, socket.assigns.result.ref_id}
    result = check(socket.assigns.client_ip, fn -> look_up(parsed, last_name) end)
    {:noreply, assign(socket, :result, result)}
  end

  defp assign_result(socket, result, input) do
    socket
    |> assign(:result, result)
    |> assign(:form, to_form(%{"ref" => input, "last_name" => ""}, as: "check"))
  end

  defp check(ip, look_up) do
    if VerifyLimit.limited?(ip) do
      %{status: :limited}
    else
      result = look_up.()
      if result.status == :not_found, do: VerifyLimit.miss(ip)
      result
    end
  end

  defp look_up(nil), do: %{status: :not_found}

  defp look_up(parsed) do
    parsed |> TaxCreditLetter.find_by_ref_id() |> found()
  end

  defp look_up(parsed, last_name) do
    parsed |> TaxCreditLetter.find_by_ref_id(last_name) |> found()
  end

  defp found(%TaxCreditLetter{} = letter) do
    %{
      status: :issued,
      ref_id: letter.ref_id,
      member: letter.member,
      team: letter.member.team,
      year: letter.year,
      certified_at: letter.inserted_at,
      primary_minutes: letter.primary_minutes,
      secondary_minutes: letter.secondary_minutes
    }
  end

  defp found(nil), do: %{status: :not_found}

  def render(%{result: nil} = assigns) do
    ~H"""
    <div id="start">
      <h1 class="heading">Verify a tax credit letter</h1>
      <p class="text-text-muted">
        Enter the reference number from the bottom of the letter.
      </p>

      <.form for={@form} id="check-form" phx-submit="check">
        <.input
          field={@form[:ref]}
          label="Reference number"
          placeholder="SRVTC-XXXXXXXX"
          autocomplete="off"
          autocapitalize="characters"
          spellcheck="false"
          class="font-mono"
        />
        <.button size={:lg} class="w-full">Verify letter</.button>
      </.form>

      <section class="small-print">
        <h2>How it works</h2>
        <p>
          Teams make tax credit letters in SAR Duty. This page shows the hours the team issued
          for a reference number. They should match the paper letter.
        </p>
      </section>
    </div>
    """
  end

  def render(%{result: %{status: :needs_last_name}} = assigns) do
    ~H"""
    <div id="needs-last-name">
      <h1 class="heading">Verify a tax credit letter</h1>
      <p class="text-text-muted">
        Older letters need the member's last name too. Enter it as it is on the letter.
      </p>

      <.form for={@form} id="last-name-form" phx-submit="check_name">
        <p class="mono">{@result.ref_id}</p>
        <.input field={@form[:last_name]} label="Last name" autocomplete="off" spellcheck="false" />
        <.button size={:lg} class="w-full">Verify letter</.button>
      </.form>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.result result={@result} />
    <div class="mt-6">
      <.button id="check-another" navigate={~p"/letters"} size={:lg} class="w-full">
        Verify another letter
      </.button>
    </div>
    """
  end

  defp result(%{result: %{status: :limited}} = assigns) do
    ~H"""
    <div id="result-limited">
      <.band kind={:danger} title="Too many tries">Wait a few minutes and try again</.band>
      <.panel>Too many reference numbers from this connection did not match a letter.</.panel>
    </div>
    """
  end

  defp result(%{result: %{status: :not_found}} = assigns) do
    ~H"""
    <div id="result-not-found">
      <.band kind={:danger} title="No tax credit letter has this reference number">
        Check the number and try again
      </.band>
      <.panel>
        Reference numbers start with SRVTC, at the bottom of the letter. Only a team's
        current letter verifies.
      </.panel>
    </div>
    """
  end

  defp result(assigns) do
    ~H"""
    <div id="result-issued">
      <.band kind={:success} title="Issued by the team">
        Verified just now
      </.band>

      <.panel>
        <h2 id="result-name" class="heading mb-0">{@result.member.name}</h2>
        <p class="hint mono mb-0">{@result.ref_id}</p>

        <div class="card-section media">
          <img
            src={"#{Web.Endpoint.url()}/teams/#{@result.team.subdomain}/logo?shape=square"}
            alt=""
            class="logo-md"
          />
          <p id="result-team" class="subheading mb-0">{@result.team.name}</p>
        </div>

        <div class="flex justify-between gap-4 mt-4">
          <.fact label="Year">{@result.year}</.fact>
          <.fact label="Certified on" class="text-right whitespace-nowrap">
            {Format.date_long(@result.certified_at, @result.team.timezone)}
          </.fact>
        </div>

        <div
          :if={@result.primary_minutes && @result.secondary_minutes}
          id="result-hours"
          class="card-section value-rows"
        >
          <.hours label="Primary hours" minutes={@result.primary_minutes} />
          <.hours label="Secondary hours" minutes={@result.secondary_minutes} />
          <.hours label="Total hours" minutes={@result.primary_minutes + @result.secondary_minutes} />
        </div>
        <p :if={!@result.primary_minutes} id="result-no-hours" class="mt-4 mb-0 text-text-muted">
          This letter's hours were not saved. Contact the team to confirm them.
        </p>
      </.panel>

      <p id="result-check" class="callout mt-4 text-sm">
        <b>Compare these hours with the paper letter.</b> If they are not the same, contact the team.
      </p>

      <.contact team={@result.team} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :minutes, :integer, required: true

  defp hours(assigns) do
    ~H"""
    <div>
      <span>{@label}</span>
      <strong>{Format.duration(@minutes)}</strong>
    </div>
    """
  end

  attr :team, :map, required: true

  defp contact(assigns) do
    assigns =
      assign(
        assigns,
        :lines,
        Enum.reject(
          [
            assigns.team.authorized_by_name,
            assigns.team.authorized_by_title,
            assigns.team.authorized_by_phone,
            assigns.team.authorized_by_email
          ],
          &(&1 in [nil, ""])
        )
      )

    ~H"""
    <section :if={@lines != []} id="result-contact" class="small-print">
      <h2>Questions about this letter</h2>
      <p>
        <%= for {line, index} <- Enum.with_index(@lines) do %>
          <br :if={index > 0} />{line}
        <% end %>
      </p>
    </section>
    """
  end
end
