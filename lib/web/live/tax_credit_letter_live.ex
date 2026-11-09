defmodule Web.TaxCreditLetterLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.CountTaxCreditHours
  alias App.Operation.EmailTaxCreditLetter
  alias App.Operation.PublishTaxCreditLetter
  alias App.Operation.WithdrawDocument

  # A tax credit letter, a published PDF (#970): what its verify page shows, Download,
  # Email letter, and Withdraw. While its year is open and attendance no longer adds up
  # to its hours, it's out of date, and Publish again prints a new one with a new ID. A
  # replaced or withdrawn letter says so and still downloads.
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
    letter = App.Repo.preload(letter, [:user, :withdrawn_by, :replaced_by])

    hours =
      team
      |> CountTaxCreditHours.call(letter.year, [letter.member_id])
      |> CountTaxCreditHours.get(letter.member_id)

    socket
    |> assign(:letter, letter)
    |> assign(:status, PublishedPDF.status(letter))
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
      <:item label={code(@letter)} />
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
        :if={@status == :current}
        id="email-letter"
        phx-click="email"
        phx-disable-with="Sending…"
        {email_confirm(@letter)}
      >
        Email letter
      </.button>
      <:trailing>
        <.button
          :if={@status == :current}
          id="withdraw-letter"
          variant={:danger}
          phx-click="withdraw"
          {withdraw_confirm(@letter)}
        >
          Withdraw letter
        </.button>
      </:trailing>
    </.form_actions>
    <hr class="my-4" />

    <.banner :if={@status == :replaced} id="letter-replaced" kind={:warning} title="Replaced">
      <p>
        Published again on {Service.Format.date_long(
          @letter.replaced_by.inserted_at,
          @current_team.timezone
        )}.
        This letter's verify page says Replaced.
      </p>
      <.button
        id="current-letter"
        navigate={~p"/teams/#{@current_team}/tax-credit-letters/#{@letter.replaced_by_id}"}
      >
        Open the new letter
      </.button>
    </.banner>

    <.banner :if={@status == :withdrawn} id="letter-withdrawn" kind={:danger} title="Withdrawn">
      <p>
        Withdrawn on {Service.Format.date_long(@letter.withdrawn_at, @current_team.timezone)}<span :if={
          @letter.withdrawn_by
        }> by {@letter.withdrawn_by.email}</span>.
        Its verify page says so, and {@letter.member.name} lists under No letter again.
      </p>
    </.banner>

    <.banner
      :if={@status == :current and @hours_status == :changed}
      id="hours-changed"
      kind={:warning}
      title="Out of date"
    >
      <p>
        This letter says {format_minutes(TaxCreditLetter.total_minutes(@letter))}.
        Attendance now adds up to {format_minutes(@hours.total_minutes)}.
        Publish it again to use the new hours. It gets a new ID and is not emailed.
        This letter's verify page then says Replaced.
      </p>
      <.button
        id="replace-letter"
        variant={:warning}
        phx-click="publish"
        phx-disable-with="Publishing…"
        {publish_confirm(@letter, @hours)}
      >
        Publish again
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
          <dt>Published</dt>
          <dd>
            {Service.Format.datetime_short(@letter.inserted_at, @current_team.timezone)}
            <span :if={@letter.user} class="hint"><br />by {@letter.user.email}</span>
          </dd>
          <dt>ID</dt>
          <dd>
            <.copy_button
              id="letter-reference"
              value={code(@letter)}
              text={code(@letter)}
              label="Copy ID"
            />
              <br />
            <.a id="letter-verify" href={PublishedPDF.verify_link(@letter.code)} external>Verify letter</.a>
          </dd>
          <%= if @letter.email_status do %>
            <dt>Email</dt>
            <dd id="letter-email-status">{email_status(@letter.email_status)}</dd>
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
        <h2 class="heading">What its verify page shows</h2>
        <p class="hint measure">
          Anyone holding the letter can check it with its verify code, at the bottom of each page.
        </p>
        <div id="letter-shows" class="value-rows measure">
          <div :for={shown <- @letter.shows}>
            <span>{shown["label"]}</span>
            <strong>{shown["text"]}</strong>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp code(letter), do: PublishedPDF.format_code(letter.code)

  defp email_status(:sending), do: "Sending"
  defp email_status(:sent), do: "Sent"
  defp email_status(:failed), do: "Did not send. Email it again."

  # Publishing again and withdrawing both end this letter's ID verifying as current, so
  # each asks for the box ticked.
  defp publish_confirm(letter, hours) do
    %{
      "data-confirm" =>
        "Publish letter #{code(letter)} again with #{format_minutes(hours.total_minutes)}? It gets a new ID and is not emailed.",
      "data-confirm-warning" => "The member needs the new letter.",
      "data-confirm-check" => "I understand this letter's verify page says Replaced.",
      "data-confirm-button" => "Publish again"
    }
  end

  # Says where it goes. With no email there's nothing to confirm; sending says so.
  defp email_confirm(%{member: %{email: email}} = letter) when is_binary(email) and email != "" do
    %{
      "data-confirm" => "Email letter #{code(letter)} to #{email}?",
      "data-confirm-button" => "Email letter"
    }
  end

  defp email_confirm(_letter), do: %{}

  defp withdraw_confirm(letter) do
    %{
      "data-confirm" => "Withdraw letter #{code(letter)}? Nothing takes its place.",
      "data-confirm-warning" => "The member may already have it. Its verify page says Withdrawn.",
      "data-confirm-check" => "I understand #{code(letter)} no longer verifies.",
      "data-confirm-button" => "Withdraw letter"
    }
  end

  def handle_event("email", _unsigned_params, socket) do
    {:noreply, put_email_flash(socket, socket.assigns.letter)}
  end

  def handle_event("publish", _unsigned_params, socket) do
    %{current_team: team, current_user: user, letter: letter} = socket.assigns

    if socket.assigns.status == :current and socket.assigns.hours_status == :changed do
      case PublishTaxCreditLetter.call(team, letter.member_id, letter.year, user, letter.id) do
        {:ok, new} ->
          message =
            "Letter published again. #{code(new)} says #{format_minutes(TaxCreditLetter.total_minutes(new))}."

          {:noreply,
           socket
           |> put_flash(:info, message)
           |> push_patch(to: ~p"/teams/#{team}/tax-credit-letters/#{new.id}")}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("withdraw", _unsigned_params, socket) do
    %{current_team: team, current_user: user, letter: letter} = socket.assigns

    case WithdrawDocument.call(team, letter, user, DateTime.utc_now()) do
      {:ok, letter} ->
        {:noreply,
         socket
         |> assign_letter(%{letter | member: socket.assigns.letter.member})
         |> put_flash(:info, "Tax credit letter withdrawn.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp put_email_flash(socket, letter) do
    case EmailTaxCreditLetter.call(letter) do
      :ok ->
        socket
        |> assign_letter(letter |> App.Repo.reload!() |> Map.put(:member, letter.member))
        |> put_flash(:info, "Emailed the tax credit letter to #{letter.member.email}.")

      {:error, :no_email} ->
        put_flash(socket, :error, "#{letter.member.name} has no email.")

      {:error, _reason} ->
        put_flash(socket, :error, "The email did not send. Try again.")
    end
  end

  defp format_minutes(minutes), do: Service.Format.duration(minutes)
end
