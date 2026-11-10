defmodule Web.TaxCreditLetterLive do
  use Web, :live_view_app_layout

  import Web.Components.PublishedPDF

  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.EmailTaxCreditLetters
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.WithdrawDocument
  alias App.ViewData.PublishedHistory
  alias Web.TaxCreditLetterConfirm

  # A member's tax credit letter for a year (#970), sent or not: the letters list's name
  # opens it. Out of date and Needed to publish are warning banners under the title
  # (#995). With a letter, the Published section a form's page has: when and who, its
  # ID, where its email is, Download, Email letter, and Withdraw letter. With none yet,
  # Not published and Email letter. A member with no email gets Publish letter, the same
  # action (App.Operation.EmailTaxCreditLetters). Page 1 shows either way, the draft
  # with the team's signature, and History lists every letter for the year.
  def mount(_params, _session, socket), do: {:ok, socket}

  @doc "The year in the path, or nil when it can't have letters."
  def parse_year(param) do
    case param |> to_string() |> Integer.parse() do
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
     # A year that isn't over can't be emailed yet: the button says so, with no confirm.
     |> assign(refusal: EmailTaxCreditLetters.refusal(year, team, DateTime.utc_now()))
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

    letter = current(pdfs, member)
    read = PrintTaxCreditLetter.read(team, member.id, year, now)
    record = record(team, member, letter, read, now)
    names = PublishedHistory.names(pdfs, &Member.name_for_user(team, &1, now))

    assign(socket,
      letter: letter,
      record: record,
      needed: needed(record, read),
      email_state: letter && TaxCreditLetter.email_state(letter, member),
      published_by: letter && names[letter.user_id],
      history: PublishedHistory.rows(pdfs, names)
    )
  end

  # What publishing needs, while Email would publish (#995).
  defp needed(record, read) do
    if EmailTaxCreditLetters.publishes?(record.email),
      do: PrintTaxCreditLetter.needed(read),
      else: []
  end

  # The letter as Email finds it (EmailTaxCreditLetters.what/1), with the hours it reads.
  defp record(team, member, letter, read, now) do
    today = PrintTaxCreditLetter.today(team, read)
    primary = today.keep["hours.primary"] || 0
    secondary = today.keep["hours.secondary"] || 0
    changes = if letter, do: TaxCreditLetter.changes(letter, today, now, team.timezone), else: []

    record = %{
      member: member,
      letter: letter,
      changes: changes,
      primary_minutes: primary,
      secondary_minutes: secondary,
      total_minutes: primary + secondary
    }

    Map.put(record, :email, EmailTaxCreditLetters.what(record))
  end

  defp current(pdfs, member) do
    case Enum.find(pdfs, &(PublishedPDF.status(&1) == :current)) do
      nil -> nil
      letter -> %{letter | member: member}
    end
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
      <aside class="content-1/3">
        <dl>
          <dt>Member</dt>
          <dd>
            <.a navigate={~p"/teams/#{@current_team}/members/#{@member.id}?when=#{@year}"}>{@member.name}</.a>
            <br /><.email id="letter-member-email" email={@member.email} />
          </dd>
          <dt>{if @letter, do: "Hours now", else: "Hours"}</dt>
          <dd id="letter-hours-now">
            {Service.Format.duration(@record.total_minutes)}
            <span class="hint block">
              {Service.Format.duration(@record.primary_minutes)} primary, {Service.Format.duration(
                @record.secondary_minutes
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

      <main class="content-2/3">
        <.out_of_date
          id="letter-out-of-date"
          noun="letter"
          changes={@record.changes}
          next={"#{email_label(@member)} makes a new one#{if emailed?(@member), do: " and sends it"}."}
        />
        <.needed_banner
          id="letter-needed"
          what="This letter"
          needed={@needed}
          team={@current_team}
          action={if emailed?(@member), do: :email, else: :publish}
        />
        <%= if @letter do %>
          <.published_section
            prefix="letter"
            pdf={@letter}
            published_by={@published_by}
            team={@current_team}
          >
            <:status>
              <p id="letter-email">
                <.email_state state={@email_state} letter={@letter} team={@current_team} />
              </p>
            </:status>
            <:actions>
              <.email_button record={@record} ask={is_nil(@refusal) and @needed == []} />
            </:actions>
            <:withdraw>
              <.button
                id="withdraw-letter"
                variant={:danger}
                phx-click="withdraw"
                phx-disable-with="Withdrawing…"
                {TaxCreditLetterConfirm.withdraw_one(@letter, @member)}
              >
                Withdraw letter
              </.button>
            </:withdraw>
          </.published_section>
          <.page_one
            prefix="letter"
            open
            src={~p"/teams/#{@current_team}/pdfs/#{@letter.id}/preview.png"}
            alt={"Page 1 of letter #{PublishedPDF.format_code(@letter.code)}"}
          />
        <% else %>
          <section id="letter-not-published" class="mb-8">
            <h2 class="heading">Not published</h2>
            <div class="card">
              <p class="mb-4">No letter for {@year} yet. This is how it prints today.</p>
              <.email_button
                record={@record}
                variant={:primary}
                ask={is_nil(@refusal) and @needed == []}
              />
              <p :if={is_nil(@record.email)} id="letter-no-hours" class="hint">
                {@member.name} has no hours in {@year}, so there is no letter to email.
              </p>
            </div>
          </section>
          <.page_one
            prefix="letter"
            open
            src={
              ~p"/teams/#{@current_team}/tax-credit-letters/#{@year}/members/#{@member.id}/draft.png"
            }
            alt="Page 1 of the letter as it prints today, marked DRAFT"
          />
        <% end %>

        <.history id="letter-history" rows={@history} team={@current_team} />
      </main>
    </div>
    """
  end

  attr :record, :map, required: true
  attr :ask, :boolean, required: true, doc: "false when it can only refuse: no confirm for that"
  attr :variant, :atom, default: :default

  # Email letter, or Publish letter for a member with no email: the same action. It
  # stays on while the year is under way or a value it needs is blank, and says why.
  defp email_button(assigns) do
    ~H"""
    <.button
      :if={@record.email}
      id="email-letter"
      variant={@variant}
      phx-click="email"
      phx-disable-with={if emailed?(@record.member), do: "Sending…", else: "Publishing…"}
      {if @ask, do: TaxCreditLetterConfirm.email_one(@record), else: %{}}
    >
      {email_label(@record.member)}
    </.button>
    """
  end

  defp emailed?(member), do: EmailTaxCreditLetters.emailed?(member)
  defp email_label(member), do: if(emailed?(member), do: "Email letter", else: "Publish letter")

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
    <b>Not emailed</b>
    <span class="hint">{@letter.member.name} has no email. It is on Your membership.</span>
    """
  end

  defp email_state(assigns) do
    ~H"""
    <b>Not emailed</b>
    """
  end

  defp code(letter), do: PublishedPDF.format_code(letter.code)

  def handle_event("email", _params, socket) do
    %{current_team: team, current_user: user, member: member, year: year} = socket.assigns

    socket =
      case EmailTaxCreditLetters.call_one(team, member, year, user) do
        {:ok, result} -> put_email_flash(socket, member, result)
        {:error, message} -> put_flash(socket, :error, message)
      end

    {:noreply, assign_letter(socket)}
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

  # What Email did: published first or not, and whether the email went.
  defp put_email_flash(socket, member, %{letter: letter, published: published, email: email}) do
    published = if published, do: "Published letter #{code(letter)}"

    case {email, published} do
      {:ok, nil} ->
        put_flash(socket, :info, "Emailed the letter to #{member.email}.")

      {:ok, published} ->
        put_flash(socket, :info, "#{published} and emailed it to #{member.email}.")

      {:no_email, published} ->
        put_flash(
          socket,
          :info,
          "#{published}. #{Member.first_name(member)} has no email, so it is on Your membership only."
        )

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
