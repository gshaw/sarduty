defmodule Web.TaxCreditLetterCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.Model.Standing
  alias App.Operation.CreateTaxCreditLetters
  alias App.Operation.EmailTaxCreditLetter
  alias App.Operation.PublishTaxCreditLetter
  alias App.ViewModel.TaxCreditLetterFilterViewModel
  alias App.Worker.CreateTaxCreditLettersWorker

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, CreateTaxCreditLetters.topic(team.id))

    {:ok, assign(socket, sending: nil, sent: nil)}
  end

  def handle_params(params, _uri, socket) do
    case TaxCreditLetterFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} ->
        socket =
          socket
          |> assign(:page_title, "#{filter_options.year} tax credit letters")
          |> assign(:filter_options, filter_options)
          |> assign(:form, to_form(changeset, as: "form"))
          |> assign(:path_fn, build_path_fn(socket.assigns.current_team, filter_options))
          |> assign_records()

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">{@page_title}</h1>

    <.sent_banner :if={@sent} sent={@sent} />
    <.banner :if={@sending} id="letters-sending" title="Sending letters" role="status">
      <p>
        Creating and emailing {Service.Format.count(@sending.count,
          one: "%d tax credit letter",
          many: "%d tax credit letters"
        )} for {@sending.year}. This page updates when they are done.
      </p>
    </.banner>
    <.send_all
      :if={!@sending && @to_send != []}
      count={length(@to_send)}
      no_email={no_email(@to_send)}
      year={@filter_options.year}
      team={@current_team}
    />

    <.stat_switch id="letter-switch" label="Letters">
      <:view
        :for={{label, letter} <- TaxCreditLetterFilterViewModel.letter_kinds()}
        id={"letter-view-#{letter || "all"}"}
        patch={@path_fn.(letter: letter)}
        current={@filter_options.letter == letter}
        count={Map.get(@letter_counts, letter, 0)}
      >
        {label}
      </:view>
    </.stat_switch>

    <.filter_bar
      for={@form}
      id="tax_credit_letter_filter_form"
      count={Service.Format.count(Enum.count(@records), one: "%d member", many: "%d members")}
      repeats
      clear={@path_fn.(:reset)}
      path_fn={@path_fn}
      hidden={[@form[:sort], @form[:letter]]}
    >
      <:search field={@form[:q]} />
      <:filter
        field={@form[:year]}
        label="Year"
        options={TaxCreditLetterFilterViewModel.years(@current_team)}
        default={Integer.to_string(TaxCreditLetterFilterViewModel.default_year())}
      />
      <:filter
        field={@form[:filter]}
        label="Hours"
        options={TaxCreditLetterFilterViewModel.filters()}
        default="any"
      />
    </.filter_bar>

    <.table
      id="member_collection"
      rows={@records}
      sort={@filter_options.sort}
      path_fn={@path_fn}
      class="table-striped"
    >
      <:header_row>
        <th colspan="2"></th>
        <th colspan="3" class="text-center">Tax credit hours</th>
        <th></th>
      </:header_row>
      <:col :let={record} label="Member" sorts={[{"↑", "name"}]}>
        <.member_cell
          member={record.member}
          team={@current_team}
          standing={@standings[record.member.id]}
          path={
            ~p"/teams/#{@current_team}/tax-credit-letters/#{@filter_options.year}/members/#{record.member.id}"
          }
        />
      </:col>
      <:col :let={record} label="Letter" class="whitespace-nowrap">
        <.letter_cell record={record} />
      </:col>

      <:col
        :let={record}
        label="Primary"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "primary"}]}
      >
        <.hours_cell minutes={record.primary_minutes} />
      </:col>
      <:col
        :let={record}
        label="Secondary"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "secondary"}]}
      >
        <.hours_cell minutes={record.secondary_minutes} />
      </:col>
      <:col
        :let={record}
        label="Total"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "total"}]}
      >
        <.hours_cell minutes={record.total_minutes} />
      </:col>
      <:col :let={record} label="" class="w-px whitespace-nowrap">
        <.button
          :if={is_nil(record.tax_credit_letter_id)}
          id={"send-letter-#{record.member.id}"}
          variant={:success}
          size={:sm}
          phx-click="create"
          value={record.member.id}
          phx-disable-with="Sending…"
        >
          Send letter
        </.button>
      </:col>
    </.table>
    """
  end

  defp send_all(assigns) do
    ~H"""
    <div id="send-all" class="mb-4 flex flex-wrap items-center gap-4">
      <.button
        id="send-all-button"
        variant={:success}
        phx-click="send_all"
        {send_all_confirm(@count, @no_email, @year, @team)}
      >
        Send {Service.Format.count(@count, one: "%d letter", many: "%d letters")}
      </.button>
      <span class="hint">
        Creates and emails a letter to each member shown with hours and no letter yet.
      </span>
      <.warning_text :if={!@team.signature} id="send-all-unsigned" class="w-full">
        These letters go out unsigned. Add the signer's signature in
        <.a navigate={~p"/teams/#{@team}/settings/tax-credit-letters"}>team settings</.a>
        first.
      </.warning_text>
    </div>
    """
  end

  # The members shown who get a letter but no email, by name.
  defp no_email(to_send) do
    for(record <- to_send, !CreateTaxCreditLetters.emailed?(record.member), do: record.member)
    |> Enum.sort_by(& &1.name)
  end

  # The check counts who gets the email, so it leaves out the members with no email.
  defp send_all_confirm(count, no_email, year, team) do
    letters = Service.Format.count(count, one: "%d letter", many: "%d letters")
    unsigned = if team.signature, do: [], else: ["They go out unsigned."]

    not_emailed =
      if no_email == [],
        do: [],
        else: [
          "No email, so not emailed: #{Service.Format.and_list(Enum.map(no_email, & &1.name))}."
        ]

    send_confirm(
      count - length(no_email),
      "Create and email #{letters} for #{year}?",
      ["Each member shown with hours and no letter yet gets one." | unsigned] ++ not_emailed
    )
  end

  defp sent_banner(assigns) do
    ~H"""
    <.banner id="letters-sent" kind={:success} title="Letters created">
      <p>
        <strong>
          {Service.Format.count(@sent.created,
            one: "%d tax credit letter",
            many: "%d tax credit letters"
          )} created for {@sent.year}. {emailing_text(@sent)}
        </strong>
        <span :if={@sent.emailing > 0}>A row shows when its email fails.</span>
      </p>
      <p :if={@sent.no_email != []} id="letters-no-email">
        No email, so not emailed: {Enum.map_join(@sent.no_email, ", ", & &1.name)}.
      </p>
    </.banner>
    """
  end

  defp emailing_text(%{emailing: 0}), do: nil
  defp emailing_text(%{emailing: count, created: count}), do: "Emailing them now."

  defp emailing_text(%{emailing: count}),
    do:
      Service.Format.count(count,
        one: "Emailing %d of them now.",
        many: "Emailing %d of them now."
      )

  # Where the member's letter is, in a word, with a badge when it needs a team admin:
  # Out of date, Did not send, or No email (#970).
  defp letter_cell(%{record: %{tax_credit_letter_id: nil}} = assigns) do
    ~H"""
    <span class="hint">No letter</span>
    """
  end

  defp letter_cell(assigns) do
    ~H"""
    <span id={"letter-state-#{@record.member.id}"}>{letter_word(@record.letter_email_state)}</span>
    <.badge
      :if={@record.letter_email_state == :failed}
      id={"letter-email-failed-#{@record.member.id}"}
      kind={:warning}
      title="Open the letter to email it again"
    >
      Did not send
    </.badge>
    <.badge
      :if={@record.letter_email_state == :no_email}
      id={"letter-no-email-#{@record.member.id}"}
      kind={:warning}
      title="Needs attention lists the members with no email"
    >
      No email
    </.badge>
    <.badge
      :if={@record.letter_hours_status == :changed}
      id={"hours-changed-#{@record.member.id}"}
      kind={:warning}
      title={"The letter says #{Service.Format.duration(@record.letter_minutes)}"}
    >
      Out of date
    </.badge>
    """
  end

  defp letter_word(:emailed), do: "Emailed"
  defp letter_word(:sending), do: "Emailing"
  defp letter_word(_not_emailed), do: "Not emailed"

  def handle_event("create", %{"value" => member_id}, socket) do
    %{current_team: team, current_user: user, filter_options: filter_options} = socket.assigns

    case PublishTaxCreditLetter.call(team, member_id, filter_options.year, user, nil) do
      {:ok, letter} -> {:noreply, socket |> assign_records() |> put_email_flash(letter)}
      {:error, message} -> {:noreply, socket |> assign_records() |> put_flash(:error, message)}
    end
  end

  def handle_event("send_all", _params, socket) do
    %{current_team: team, filter_options: filter_options, to_send: to_send} = socket.assigns

    member_ids = Enum.map(to_send, & &1.member.id)

    CreateTaxCreditLettersWorker.enqueue(
      team,
      filter_options.year,
      member_ids,
      socket.assigns.current_user
    )

    {:noreply,
     assign(socket, sending: %{count: length(to_send), year: filter_options.year}, sent: nil)}
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case TaxCreditLetterFilterViewModel.validate(form_params) do
      {:ok, filter_options, _changeset} ->
        path = build_filter_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp assign_records(socket) do
    %{filter_options: filter_options, current_team: team} = socket.assigns
    all = TaxCreditLetterFilterViewModel.find_all(team, filter_options)
    records = TaxCreditLetterFilterViewModel.shown(all, filter_options)
    members = Enum.map(records, & &1.member)

    socket
    # The tiles count the search too (#935): a search shows on them where its matches are.
    |> assign(
      :letter_counts,
      all
      |> TaxCreditLetterFilterViewModel.shown(%{filter_options | letter: nil})
      |> TaxCreditLetterFilterViewModel.letter_counts()
    )
    |> assign(:records, records)
    |> assign(:standings, Standing.by_member(team, members, DateTime.utc_now()))
    |> assign(
      :to_send,
      Enum.filter(records, &(is_nil(&1.tax_credit_letter_id) and &1.total_minutes > 0))
    )
  end

  def handle_info({:tax_credit_letters_sent, summary}, socket) do
    {:noreply, socket |> assign(sending: nil, sent: summary) |> assign_records()}
  end

  # One letter's email job is done: its row says whether it went.
  def handle_info({:tax_credit_letter_emailed, _letter_id}, socket),
    do: {:noreply, assign_records(socket)}

  # Swoosh's test adapter tells the process that sent the email, which in tests is this
  # one, since Oban runs the job inline.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  defp build_path_fn(team, filter_options) do
    fn changed_options ->
      case changed_options do
        :reset ->
          build_filter_path(team, %TaxCreditLetterFilterViewModel{})

        _ ->
          build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  defp build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/teams/#{team}/tax-credit-letters?#{query_params}"
  end

  defp put_email_flash(socket, letter) do
    case EmailTaxCreditLetter.send_now(letter) do
      :ok ->
        put_flash(socket, :info, "Emailed the tax credit letter to #{letter.member.email}.")

      {:error, :no_email} ->
        put_flash(
          socket,
          :error,
          "Published the letter. #{letter.member.name} has no email."
        )

      {:error, _reason} ->
        put_flash(
          socket,
          :error,
          "Published the letter, but the email did not send. Open the letter to try again."
        )
    end
  end
end
