defmodule Web.TaxCreditLetterCollectionLive do
  use Web, :live_view_app_layout

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
    <.breadcrumbs team={@current_team}>
      <:item label={@page_title} />
    </.breadcrumbs>

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
    <.form
      for={@form}
      id="tax_credit_letter_filter_form"
      phx-change="change"
      phx-submit="change"
      class="filter-form"
    >
      <.input
        label="Year"
        field={@form[:year]}
        type="select"
        options={TaxCreditLetterFilterViewModel.years(@current_team)}
      />
      <.input field={@form[:q]} label="Search" />
      <.input
        label="Sort"
        field={@form[:sort]}
        type="select"
        options={TaxCreditLetterFilterViewModel.sort_kinds()}
      />
      <.input
        label="Hours"
        field={@form[:filter]}
        type="select"
        options={TaxCreditLetterFilterViewModel.filters()}
      />
    </.form>

    <.send_all
      :if={!@sending && @to_send != []}
      count={length(@to_send)}
      year={@filter_options.year}
      team={@current_team}
    />

    <div class="table-summary">
      <span class="table-summary-links">
        <.a navigate={@path_fn.(:reset)}>Reset filters</.a>
      </span>
      <span class="table-summary-count">
        {Service.Format.count(Enum.count(@records), one: "%d member", many: "%d members")}
      </span>
    </div>

    <.table
      id="member_collection"
      rows={@records}
      sort={@filter_options.sort}
      path_fn={@path_fn}
      class="table-striped"
    >
      <:header_row>
        <th colspan="3"></th>
        <th colspan="3" class="text-center">SARVAC hours</th>
        <th></th>
      </:header_row>
      <:col :let={record} label="ID" class="w-px" sorts={[{"↑", "id"}]}>
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Name" sorts={[{"↑", "name"}]}>
        <.a navigate={
          ~p"/teams/#{@current_team}/members/#{record.member.id}?tag=both&when=#{@filter_options.year}"
        }>
          {record.member.name}
        </.a>
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
        {Service.Format.duration_as_hours_minutes_medium(record.primary_minutes)}
      </:col>
      <:col
        :let={record}
        label="Secondary"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "secondary"}]}
      >
        {Service.Format.duration_as_hours_minutes_medium(record.secondary_minutes)}
      </:col>
      <:col
        :let={record}
        label="Total"
        align="right"
        class="w-px whitespace-nowrap"
        sorts={[{"↓", "total"}]}
      >
        {Service.Format.duration_as_hours_minutes_medium(record.total_minutes)}
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
        <.a navigate={~p"/teams/#{@team}/settings"}>team settings</.a>
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
    <.banner id="letters-sent" kind={:success} title="Letters sent">
      <p>
        <strong>
          {Service.Format.count(@sent.created,
            one: "%d tax credit letter",
            many: "%d tax credit letters"
          )} created for {@sent.year}. {@sent.emailed} emailed.
        </strong>
      </p>
      <p :if={@sent.no_email != []} id="letters-no-email">
        No email in D4H, so not emailed: {Enum.map_join(@sent.no_email, ", ", & &1.name)}.
      </p>
      <p :if={@sent.failed != []} id="letters-failed">
        The email did not send to {Enum.map_join(@sent.failed, ", ", & &1.name)}. Open
        their letters to try again.
      </p>
    </.banner>
    """
  end

  defp record_actions(assigns) do
    ~H"""
    <%= if @record.tax_credit_letter_id do %>
      <.a navigate={~p"/teams/#{@current_team}/tax-credit-letters/#{@record.tax_credit_letter_id}"}>
        <span class="mono">{@record.tax_credit_letter_ref_id}</span>
      </.a>
      <.badge
        :if={@record.letter_hours_status == :changed}
        id={"hours-changed-#{@record.tax_credit_letter_id}"}
        kind={:warning}
        title={"The letter says #{Service.Format.duration_as_hours_minutes_medium(@record.letter_minutes)}"}
      >
        Hours changed
      </.badge>
    <% else %>
      <.button variant={:success} size={:sm} phx-click="create" value={@record.member.id}>
        Create letter
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

    %{
      team_id: team.id,
      year: filter_options.year,
      member_ids: Enum.map(to_send, & &1.member.id),
      user_id: socket.assigns.current_user.id
    }
    |> CreateTaxCreditLettersWorker.new()
    |> Oban.insert!()

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
    records =
      TaxCreditLetterFilterViewModel.find_all(
        socket.assigns.current_team,
        socket.assigns.filter_options
      )

    socket
    |> assign(:records, records)
    |> assign(
      :to_send,
      Enum.filter(records, &(is_nil(&1.tax_credit_letter_id) and &1.total_minutes > 0))
    )
  end

  def handle_info({:tax_credit_letters_sent, summary}, socket) do
    {:noreply, socket |> assign(sending: nil, sent: summary) |> assign_records()}
  end

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
          "Created the letter. #{letter.member.name} has no email in D4H."
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
