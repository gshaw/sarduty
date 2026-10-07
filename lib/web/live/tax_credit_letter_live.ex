defmodule Web.TaxCreditLetterLive do
  use Web, :live_view_app_layout

  alias App.Model.TaxCreditLetter
  alias App.Operation.CountTaxCreditHours
  alias App.Operation.EmailTaxCreditLetter
  alias App.Operation.ReplaceTaxCreditLetter
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    letter = TaxCreditLetter.find!(socket.assigns.current_team, params["id"])

    socket =
      socket
      |> assign(:page_title, "#{letter.member.name}ʼs #{letter.year} tax credit letter")
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
    <.breadcrumbs team={@current_team}>
      <:item
        label={"#{@letter.year} tax credit letters"}
        path={~p"/teams/#{@current_team}/tax-credit-letters?year=#{@letter.year}"}
      />
      <:item label={@letter.ref_id} />
    </.breadcrumbs>

    <h1 class="title">{@page_title}</h1>
    <.form_actions>
      <.button
        href={~p"/teams/#{@current_team}/tax-credit-letters/#{@letter.id}/pdf"}
        variant={:success}
      >
        Download PDF
      </.button>
      <.button id="email-letter" variant={:warning} phx-click="email">Email letter</.button>
      <:trailing>
        <.button
          variant={:danger}
          phx-click="destroy"
          data-confirm={"Delete letter #{@letter.ref_id}? The member may already have it. A new letter gets a new reference number."}
        >
          Delete letter
        </.button>
      </:trailing>
    </.form_actions>
    <hr class="my-p border-hr" />

    <div
      :if={@hours_status == :changed}
      id="hours-changed"
      class="banner banner-warning"
      role="region"
      aria-label="Hours changed"
    >
      <div class="banner-title">
        <.icon name="hero-exclamation-triangle" class="size-5" />Hours changed
      </div>
      <div class="banner-body">
        <p>
          This letter says {format_minutes(TaxCreditLetter.total_minutes(@letter))}.
          Attendance now adds up to {format_minutes(@hours.total_minutes)}.
          Replace the letter to use the new hours. It keeps its reference number and is not emailed.
        </p>
        <.button
          id="replace-letter"
          variant={:warning}
          size={:sm}
          phx-click="replace"
          data-confirm={"Replace letter #{@letter.ref_id} with #{format_minutes(@hours.total_minutes)}? It is not emailed."}
        >
          Replace letter
        </.button>
      </div>
    </div>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl>
          <dt>Member</dt>
          <dd>
            <.a navigate={
              ~p"/teams/#{@current_team}/members/#{@letter.member.id}?when=#{@letter.year}"
            }>
              {@letter.member.name}
            </.a>
            <br />{@letter.member.email}
          </dd>
          <dt>Created</dt>
          <dd>{Service.Format.datetime_short(@letter.inserted_at, @current_team.timezone)}</dd>
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
          "Letter replaced. It now says #{format_minutes(TaxCreditLetter.total_minutes(letter))}."
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("destroy", _unsigned_params, socket) do
    tax_credit_letter = socket.assigns.letter
    Repo.delete!(tax_credit_letter)

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
        put_flash(socket, :error, "#{letter.member.name} has no email in D4H.")

      {:error, _reason} ->
        put_flash(socket, :error, "The email did not send. Try again.")
    end
  end

  defp format_minutes(minutes), do: Service.Format.duration_as_hours_minutes_medium(minutes)
end
