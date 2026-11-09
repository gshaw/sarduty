defmodule Web.TaxCreditLetterLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.CountTaxCreditHours
  alias App.Operation.DeleteTaxCreditLetter
  alias App.Operation.EmailTaxCreditLetter
  alias App.Operation.ReplaceTaxCreditLetter

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    letter = TaxCreditLetter.find!(socket.assigns.current_team, params["id"])

    socket =
      socket
      |> assign(:page_title, "#{letter.member.name}'s #{letter.year} tax credit letter")
      |> assign_letter(letter)

    {:noreply, socket}
  end

  defp assign_letter(socket, letter) do
    team = socket.assigns.current_team

    hours =
      team
      |> CountTaxCreditHours.call(letter.year, [letter.member_id])
      |> CountTaxCreditHours.get(letter.member_id)

    socket
    |> assign(:letter, letter)
    |> assign(:hours, hours)
    |> assign(
      :hours_status,
      TaxCreditLetter.hours_status(letter, hours, DateTime.utc_now(), team.timezone)
    )
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item
        label="Tax credit letters"
        path={~p"/teams/#{@current_team}/tax-credit-letters?year=#{@letter.year}"}
      />
      <:item label={code(@letter) || "#{@letter.year}"} />
    </.breadcrumbs>

    <h1 class="title">{@page_title}</h1>
    <.form_actions>
      <.button
        href={~p"/teams/#{@current_team}/tax-credit-letters/#{@letter.id}/pdf"}
        variant={:primary}
      >
        Download PDF
      </.button>
      <.button
        id="email-letter"
        phx-click="email"
        phx-disable-with="Sending…"
        {email_confirm(@letter)}
      >
        Email letter
      </.button>
      <:trailing>
        <.button id="delete-letter" variant={:danger} phx-click="destroy" {delete_confirm(@letter)}>
          Delete letter
        </.button>
      </:trailing>
    </.form_actions>
    <hr class="my-4" />

    <.banner
      :if={@hours_status == :changed}
      id="hours-changed"
      kind={:warning}
      title="Hours changed"
    >
      <p>
        This letter says {format_minutes(TaxCreditLetter.total_minutes(@letter))}.
        Attendance now adds up to {format_minutes(@hours.total_minutes)}.
        Replace the letter to use the new hours. It gets a new ID and is not emailed.
        The old letter's verify page then says Replaced.
      </p>
      <.button
        id="replace-letter"
        variant={:warning}
        phx-click="replace"
        phx-disable-with="Replacing…"
        {replace_confirm(@letter, @hours)}
      >
        Replace letter
      </.button>
    </.banner>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl>
          <dt>Member</dt>
          <dd>
            <.a navigate={
              ~p"/teams/#{@current_team}/members/#{@letter.member.id}?when=#{@letter.year}"
            }>{@letter.member.name}</.a>
            <br /><.email id="letter-member-email" email={@letter.member.email} />
          </dd>
          <dt>Created</dt>
          <dd>{Service.Format.datetime_short(@letter.inserted_at, @current_team.timezone)}</dd>
          <%= if @letter.pdf do %>
            <dt>ID</dt>
            <dd>
              <.copy_button
                id="letter-reference"
                value={code(@letter)}
                text={code(@letter)}
                label="Copy ID"
              />
              <%!-- A reference number from before #970 verifies nowhere. --%>
              <%= if PublishedPDF.parse_code(@letter.pdf.code) do %>
                <br />
                <.a
                  id="letter-verify"
                  href={PublishedPDF.verify_link(@letter.pdf.code)}
                  external
                >Verify letter</.a>
              <% end %>
            </dd>
          <% end %>
          <%= if @hours_status != :unknown do %>
            <dt>Hours on the letter</dt>
            <dd id="letter-hours">{format_minutes(TaxCreditLetter.total_minutes(@letter))}</dd>
          <% end %>
          <%= if @hours_status in [:changed, :changed_old] do %>
            <dt>Hours from attendance now</dt>
            <dd id="attendance-hours">{format_minutes(@hours.total_minutes)}</dd>
          <% end %>
        </dl>
      </aside>
      <main class="content-2/3">
        <.markdown content={@letter.letter_content} />
      </main>
    </div>
    """
  end

  # The letter's ID as printed, or nil for one never published.
  defp code(%{pdf: %PublishedPDF{code: code}}), do: PublishedPDF.format_code(code)
  defp code(_letter), do: nil

  defp name(letter), do: code(letter) || "for #{letter.year}"

  # Both stop the letter's ID verifying as current, so each asks for the box ticked.
  defp replace_confirm(letter, hours) do
    %{
      "data-confirm" =>
        "Replace letter #{name(letter)} with #{format_minutes(hours.total_minutes)}? It gets a new ID and is not emailed.",
      "data-confirm-warning" => "The member needs the new letter.",
      "data-confirm-check" => "I understand the old letter's verify page says Replaced.",
      "data-confirm-button" => "Replace letter"
    }
  end

  # Says where it goes. With no email there's nothing to confirm; sending says so.
  defp email_confirm(%{member: %{email: email}} = letter) when is_binary(email) and email != "" do
    %{
      "data-confirm" => "Email letter #{name(letter)} to #{email}?",
      "data-confirm-button" => "Email letter"
    }
  end

  defp email_confirm(_letter), do: %{}

  defp delete_confirm(letter) do
    %{
      "data-confirm" => "Delete letter #{name(letter)}? The member may already have it.",
      "data-confirm-warning" => "A new letter gets a new ID.",
      "data-confirm-check" => "I understand #{name(letter)} no longer verifies.",
      "data-confirm-button" => "Delete letter"
    }
  end

  def handle_event("email", _unsigned_params, socket) do
    {:noreply, put_email_flash(socket, socket.assigns.letter)}
  end

  def handle_event("replace", _unsigned_params, socket) do
    team = socket.assigns.current_team

    if socket.assigns.hours_status == :changed do
      letter = ReplaceTaxCreditLetter.call(team, socket.assigns.letter)

      socket =
        socket
        |> assign_letter(letter)
        |> put_flash(
          :info,
          "Letter replaced. #{name(letter)} says #{format_minutes(TaxCreditLetter.total_minutes(letter))}."
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("destroy", _unsigned_params, socket) do
    tax_credit_letter = socket.assigns.letter
    DeleteTaxCreditLetter.call(tax_credit_letter)

    socket =
      socket
      |> put_flash(:info, "Tax credit letter deleted.")
      |> redirect(
        to:
          ~p"/teams/#{socket.assigns.current_team}/tax-credit-letters?year=#{tax_credit_letter.year}"
      )

    {:noreply, socket}
  end

  defp put_email_flash(socket, letter) do
    case EmailTaxCreditLetter.call(letter) do
      :ok ->
        put_flash(socket, :info, "Emailed the tax credit letter to #{letter.member.email}.")

      {:error, :no_email} ->
        put_flash(socket, :error, "#{letter.member.name} has no email.")

      {:error, :not_printed} ->
        put_flash(socket, :error, "The letter's PDF didn't print. Ask for help with Get help.")

      {:error, _reason} ->
        put_flash(socket, :error, "The email did not send. Try again.")
    end
  end

  defp format_minutes(minutes), do: Service.Format.duration(minutes)
end
