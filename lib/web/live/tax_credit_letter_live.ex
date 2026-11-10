defmodule Web.TaxCreditLetterLive do
  use Web, :live_view_app_layout

  import Web.Components.PublishedPDF

  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.CountTaxCreditHours
  alias App.Operation.EmailTaxCreditLetter
  alias App.Operation.PublishTaxCreditLetter
  alias App.Operation.WithdrawDocument
  alias App.ViewData.PublishedHistory

  # A member's tax credit letter for a year (#970), sent or not: the letters list's name
  # opens it. With a letter, the Published box a form's page has: when and who, its ID,
  # where its email is, Out of date with what changed, Download, Email letter, Publish
  # again, and Withdraw. With none yet, the letter as it prints today, marked DRAFT, and
  # Send letter. Page 1 shows either way, and History lists every letter for the year.
  def mount(_params, _session, socket), do: {:ok, socket}

  @doc "The year in the path, or nil when it can't have letters."
  def parse_year(param) do
    case Integer.parse(to_string(param)) do
      {year, ""} when year >= 2014 -> if year <= Date.utc_today().year + 1, do: year
      _other -> nil
    end
  end

  def handle_params(%{"year" => year, "id" => member_id}, _uri, socket) do
    team = socket.assigns.current_team
    year = parse_year(year) || raise(Web.Status.NotFound)
    member = %{Member.find!(team, member_id) | team: team}

    {:noreply,
     socket
     |> assign(page_title: "#{member.name}'s #{year} tax credit letter")
     |> assign(member: member, year: year)
     |> assign_letter()}
  end

  defp assign_letter(socket) do
    %{current_team: team, member: member, year: year} = socket.assigns
    now = DateTime.utc_now()

    pdfs =
      PublishedPDF.get_all_for(
        team.id,
        TaxCreditLetter.name(),
        TaxCreditLetter.subject(member.id, year)
      )

    letter =
      case Enum.find(pdfs, &(PublishedPDF.status(&1) == :current)) do
        nil -> nil
        letter -> %{letter | member: member}
      end

    hours =
      team |> CountTaxCreditHours.call(year, [member.id]) |> CountTaxCreditHours.get(member.id)

    names = PublishedHistory.names(pdfs, &Member.name_for_user(team, &1, now))

    assign(socket,
      letter: letter,
      hours: hours,
      changes: changes(letter, hours, now, team.timezone),
      email_state: letter && TaxCreditLetter.email_state(letter, member),
      published_by: letter && names[letter.user_id],
      history: PublishedHistory.rows(pdfs, names)
    )
  end

  # Only a letter for last year or later can be published again (TaxCreditLetter.hours_status/4).
  defp changes(nil, _hours, _now, _timezone), do: []

  defp changes(letter, hours, now, timezone) do
    if TaxCreditLetter.hours_status(letter, hours, now, timezone) == :changed,
      do: TaxCreditLetter.changes(letter, hours),
      else: []
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item
        label={"#{@year} tax credit letters"}
        path={~p"/teams/#{@current_team}/tax-credit-letters?year=#{@year}"}
      />
      <:item label={@member.name} />
    </.breadcrumbs>

    <h1 class="title">{@page_title}</h1>

    <div class="content-wrapper">
      <main class="content-2/3">
        <%= if @letter do %>
          <section id="letter-published" class="mb-8">
            <h2 class="heading">Published</h2>
            <div class="card">
              <p class="mb-2">
                {Service.Format.datetime_short(@letter.inserted_at, @current_team.timezone)}
                <span :if={@published_by}>by {@published_by}</span>
              </p>
              <p class="mono mb-2">
                <.a id="letter-verify" href={PublishedPDF.verify_link(@letter.code)} external>{code(
                  @letter
                )}</.a>
              </p>
              <p id="letter-email" class="mb-4">
                <.email_state state={@email_state} letter={@letter} team={@current_team} />
              </p>
              <.out_of_date id="letter-out-of-date" noun="letter" changes={@changes} />
              <.form_actions>
                <.button
                  id="letter-download"
                  href={~p"/teams/#{@current_team}/pdfs/#{@letter.id}"}
                  variant={:primary}
                >
                  Download PDF
                </.button>
                <.button
                  :if={@email_state != :no_email}
                  id="email-letter"
                  phx-click="email"
                  phx-disable-with="Sending…"
                  {email_confirm(@letter)}
                >
                  Email letter
                </.button>
                <.button
                  :if={@changes != []}
                  id="replace-letter"
                  variant={:warning}
                  phx-click="publish"
                  phx-disable-with="Publishing…"
                  {publish_confirm(@member, @hours)}
                >
                  Publish again
                </.button>
                <:trailing>
                  <.button
                    id="withdraw-letter"
                    variant={:danger}
                    phx-click="withdraw"
                    phx-disable-with="Withdrawing…"
                    {withdraw_confirm(@letter, "Withdraw letter")}
                  >
                    Withdraw letter
                  </.button>
                </:trailing>
              </.form_actions>
            </div>
          </section>
          <.preview
            id="letter-preview"
            src={~p"/teams/#{@current_team}/pdfs/#{@letter.id}/preview.png"}
            alt={"Page 1 of letter #{code(@letter)}"}
          />
        <% else %>
          <section id="letter-not-published" class="mb-8">
            <h2 class="heading">Not published</h2>
            <div class="card">
              <p class="mb-4">No letter for {@year} yet. This is how it prints today.</p>
              <div class="flex flex-wrap items-center gap-4">
                <.button
                  id="send-letter"
                  variant={:success}
                  phx-click="send"
                  phx-disable-with="Sending…"
                >
                  Send letter
                </.button>
                <span class="hint">{send_hint(@member)}</span>
              </div>
            </div>
          </section>
          <.preview
            id="letter-preview"
            src={
              ~p"/teams/#{@current_team}/tax-credit-letters/#{@year}/members/#{@member.id}/draft.png"
            }
            alt="Page 1 of the letter as it prints today, marked DRAFT"
          />
        <% end %>

        <.history id="letter-history" rows={@history} team={@current_team} />
      </main>

      <aside class="content-1/3">
        <dl>
          <dt>Member</dt>
          <dd>
            <.a navigate={~p"/teams/#{@current_team}/members/#{@member.id}?when=#{@year}"}>{@member.name}</.a>
            <br /><.email id="letter-member-email" email={@member.email} />
          </dd>
          <dt>{if @letter, do: "Hours now", else: "Hours"}</dt>
          <dd id="letter-hours-now">
            {Service.Format.duration(@hours.total_minutes)}
            <span class="hint block">
              {Service.Format.duration(@hours.primary_minutes)} primary, {Service.Format.duration(
                @hours.secondary_minutes
              )} secondary
            </span>
          </dd>
          <dt>Actions</dt>
          <dd>
            <ul class="action-list">
              <li>
                <.a
                  id="letter-activities"
                  navigate={~p"/teams/#{@current_team}/members/#{@member.id}?tag=both&when=#{@year}"}
                >Activities with tax credit hours</.a>
              </li>
            </ul>
          </dd>
        </dl>
      </aside>
    </div>
    """
  end

  attr :state, :atom, required: true
  attr :letter, :map, required: true
  attr :team, :map, required: true

  # Where the letter's email is, the word the letters list shows, with when or why.
  defp email_state(%{state: :emailed} = assigns) do
    ~H"""
    <b>Emailed</b>
    <span class="hint">
      {@letter.emailed_at && Service.Format.date_short(@letter.emailed_at, @team.timezone)} to {@letter.member.email}
    </span>
    """
  end

  defp email_state(%{state: :sending} = assigns) do
    ~H"""
    <b>Emailing</b> <span class="hint">to {@letter.member.email}</span>
    """
  end

  defp email_state(%{state: :failed} = assigns) do
    ~H"""
    <b>Not emailed</b> <span class="hint">The email did not send. Email letter sends it again.</span>
    """
  end

  defp email_state(%{state: :no_email} = assigns) do
    ~H"""
    <b>Not emailed</b> <span class="hint">{@letter.member.name} has no email.</span>
    """
  end

  defp email_state(assigns) do
    ~H"""
    <b>Not emailed</b>
    """
  end

  defp code(letter), do: PublishedPDF.format_code(letter.code)

  defp send_hint(member) do
    if member.email in [nil, ""],
      do: "Publishes it. #{member.name} has no email, so it isn't emailed.",
      else: "Publishes it and emails it to #{member.email}."
  end

  # Publishing again emails the new letter, so the member never keeps one that verifies
  # as Replaced.
  defp publish_confirm(member, hours) do
    emailed =
      if member.email in [nil, ""],
        do: "#{member.name} has no email, so it isn't emailed.",
        else: "The new letter is emailed to #{member.email}."

    %{
      "data-confirm" =>
        "Publish this letter again with #{Service.Format.duration(hours.total_minutes)}?",
      "data-confirm-warning" =>
        "It gets a new ID, and this one's verify page says Replaced. #{emailed}",
      "data-confirm-button" => "Publish again"
    }
  end

  defp email_confirm(letter) do
    %{
      "data-confirm" => "Email letter #{code(letter)} to #{letter.member.email}?",
      "data-confirm-button" => "Email letter"
    }
  end

  def handle_event("email", _params, %{assigns: %{letter: %{} = letter}} = socket) do
    {:noreply, socket |> put_email_flash(letter, nil) |> assign_letter()}
  end

  def handle_event("send", _params, %{assigns: %{letter: nil}} = socket),
    do: {:noreply, publish(socket, nil, "Published the letter")}

  def handle_event("publish", _params, %{assigns: %{letter: %{} = letter}} = socket) do
    if socket.assigns.changes != [],
      do: {:noreply, publish(socket, letter.id, "Published the letter again")},
      else: {:noreply, socket}
  end

  def handle_event("withdraw", _params, %{assigns: %{letter: %{} = letter}} = socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case WithdrawDocument.call(team, letter, user, DateTime.utc_now()) do
      {:ok, _letter} ->
        {:noreply,
         socket |> put_flash(:info, "Withdrew letter #{code(letter)}.") |> assign_letter()}

      {:error, message} ->
        {:noreply, socket |> put_flash(:error, message) |> assign_letter()}
    end
  end

  # The page was out of step with another tab: show what's there now.
  def handle_event(_event, _params, socket), do: {:noreply, assign_letter(socket)}

  defp publish(socket, current_id, done) do
    %{current_team: team, current_user: user, member: member, year: year} = socket.assigns

    case PublishTaxCreditLetter.call(team, member.id, year, user, current_id) do
      {:ok, letter} ->
        socket |> put_email_flash(letter, "#{done}, #{code(letter)}") |> assign_letter()

      {:error, message} ->
        socket |> put_flash(:error, message) |> assign_letter()
    end
  end

  # `published` says what was just published, or nil for Email letter alone.
  defp put_email_flash(socket, letter, published) do
    %{name: name, email: email} = letter.member

    case {EmailTaxCreditLetter.send_now(letter), published} do
      {:ok, nil} ->
        put_flash(socket, :info, "Emailed the letter to #{email}.")

      {:ok, published} ->
        put_flash(socket, :info, "#{published}, and emailed it to #{email}.")

      {{:error, :no_email}, nil} ->
        put_flash(socket, :error, "#{name} has no email.")

      {{:error, :no_email}, published} ->
        put_flash(socket, :info, "#{published}. #{name} has no email, so it wasn't emailed.")

      {{:error, _reason}, nil} ->
        put_flash(socket, :error, "The email did not send. Try again.")

      {{:error, _reason}, published} ->
        put_flash(
          socket,
          :error,
          "#{published}, but the email did not send. Email letter sends it again."
        )
    end
  end
end
