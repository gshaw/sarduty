defmodule Web.TaxCreditLetterCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.Operation.CreateTaxCreditLetter
  alias App.Operation.CreateTaxCreditLetters
  alias App.Operation.EmailTaxCreditLetter
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
      repeats={Enum.count(@records) == Map.get(@letter_counts, @filter_options.letter, 0)}
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
      <:col :let={record} label="Name" sorts={[{"↑", "name"}]}>
        <.a navigate={
          ~p"/teams/#{@current_team}/members/#{record.member.id}?tag=both&when=#{@filter_options.year}"
        }>{record.member.name}</.a>
      </:col>
      <:col :let={record} label="Email">
        {record.member.email}
      </:col>

      <:col
        :let={record}
        label="Primary"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "primary"}]}
      >
        {Service.Format.duration(record.primary_minutes)}
      </:col>
      <:col
        :let={record}
        label="Secondary"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "secondary"}]}
      >
        {Service.Format.duration(record.secondary_minutes)}
      </:col>
      <:col
        :let={record}
        label="Total"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "total"}]}
      >
        {Service.Format.duration(record.total_minutes)}
      </:col>
      <:col :let={record} label="Letter" class="whitespace-nowrap">
        <.record_actions record={record} current_team={@current_team} />
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
        data-confirm={send_all_confirm(@count, @year, @team)}
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

  defp send_all_confirm(count, year, team) do
    letters = Service.Format.count(count, one: "%d letter", many: "%d letters")
    question = "Create and email #{letters} for #{year}?"
    if team.signature, do: question, else: question <> " They go out unsigned."
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

  defp record_actions(assigns) do
    ~H"""
    <%= if @record.tax_credit_letter_id do %>
      <.a
        class="mono"
        navigate={~p"/teams/#{@current_team}/tax-credit-letters/#{@record.tax_credit_letter_id}"}
      >{@record.tax_credit_letter_ref_id}</.a>
      <.badge
        :if={@record.letter_hours_status == :changed}
        id={"hours-changed-#{@record.tax_credit_letter_id}"}
        kind={:warning}
        title={"The letter says #{Service.Format.duration(@record.letter_minutes)}"}
      >
        Hours changed
      </.badge>
      <span
        :if={@record.tax_credit_letter_email_status == :sending}
        id={"letter-emailing-#{@record.tax_credit_letter_id}"}
        class="hint"
      >
        Emailing
      </span>
      <.badge
        :if={@record.tax_credit_letter_email_status == :failed}
        id={"letter-email-failed-#{@record.tax_credit_letter_id}"}
        kind={:warning}
        title="Open the letter to email it again"
      >
        Email failed
      </.badge>
    <% else %>
      <.button
        variant={:success}
        size={:sm}
        phx-click="create"
        value={@record.member.id}
        phx-disable-with="Sending…"
      >
        Send letter
      </.button>
    <% end %>
    """
  end

  def handle_event("create", %{"value" => member_id}, socket) do
    tax_credit_letter =
      CreateTaxCreditLetter.call(
        team: socket.assigns.current_team,
        member_id: member_id,
        year: socket.assigns.filter_options.year
      )

    socket =
      socket
      |> assign_records()
      |> put_email_flash(tax_credit_letter)

    {:noreply, socket}
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
    filter_options = socket.assigns.filter_options
    all = TaxCreditLetterFilterViewModel.find_all(socket.assigns.current_team, filter_options)
    records = TaxCreditLetterFilterViewModel.shown(all, filter_options)

    socket
    |> assign(:letter_counts, TaxCreditLetterFilterViewModel.letter_counts(all))
    |> assign(:records, records)
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
    case EmailTaxCreditLetter.call(letter) do
      :ok ->
        put_flash(socket, :info, "Emailed the tax credit letter to #{letter.member.email}.")

      {:error, :no_email} ->
        put_flash(
          socket,
          :error,
          "Created the letter. #{letter.member.name} has no email."
        )

      {:error, _reason} ->
        put_flash(
          socket,
          :error,
          "Created the letter, but the email did not send. Open the letter to try again."
        )
    end
  end
end
