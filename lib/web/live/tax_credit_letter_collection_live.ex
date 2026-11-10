defmodule Web.TaxCreditLetterCollectionLive do
  @moduledoc """
  A year's tax credit letters, one row per member (#970): each name opens the member's
  letter for the year, sent or not, and Letter says where it is. A tile per to-do over
  it filters it. Team admins check members and act on them under it: For the checked
  members, Send letters, Email letters, or Publish again, and one button in the action
  bar at the foot of the window, as on an activity's Members tab. Each choice counts
  only the checked it fits, and one that fits none greys out and says why. The ticks
  are the rows shown: a filter that hides a row unchecks it.

  Send letters runs in a job (App.Worker.CreateTaxCreditLettersWorker) and Publish again
  in the background of this page, since each prints a PDF; each email has its own job,
  and each row updates as its email goes.
  """
  use Web, :live_view_app_layout

  import Web.Components.ActionBar
  import Web.Components.FilterBar
  import Web.Components.StatSwitch

  alias App.Model.Standing
  alias App.Model.TaxCreditLetter
  alias App.Operation.CreateTaxCreditLetters
  alias App.ViewModel.TaxCreditLetterFilterViewModel
  alias App.Worker.CreateTaxCreditLettersWorker

  @choices ~w(send email publish)

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, CreateTaxCreditLetters.topic(team.id))

    {:ok,
     assign(socket,
       sending: nil,
       sent: nil,
       publishing: nil,
       selected: MapSet.new(),
       choice: nil
     )}
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
    <.banner :if={@publishing} id="letters-publishing" title="Publishing letters again" role="status">
      <p>
        Printing {Service.Format.count(@publishing,
          one: "%d new letter",
          many: "%d new letters"
        )}. This page updates when they are done.
      </p>
    </.banner>
    <.warning_text
      :if={!@current_team.signature and Enum.any?(@records, &is_nil(&1.tax_credit_letter_id))}
      id="letters-unsigned"
      class="mb-4"
    >
      Letters go out unsigned. Add the signer's signature in
      <.a navigate={~p"/teams/#{@current_team}/settings/tax-credit-letters"}>team settings</.a>
      first.
    </.warning_text>

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

    <.form
      :if={@records != []}
      for={%{}}
      id="letters-form"
      phx-change="tick"
      phx-submit="apply"
    >
      <.table
        id="member_collection"
        rows={@records}
        sort={@filter_options.sort}
        path_fn={@path_fn}
        class="table-striped"
      >
        <:header_row>
          <th colspan="3"></th>
          <th colspan="3" class="text-center">Tax credit hours</th>
        </:header_row>
        <:col :let={record} label="" class="w-px" select_all>
          <input
            type="checkbox"
            id={"letters-select-#{record.member.id}"}
            name="member_ids[]"
            value={record.member.id}
            checked={MapSet.member?(@selected, record.member.id)}
            aria-label={"Check #{record.member.name}"}
          />
        </:col>
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
      </.table>
      <div id="letters-choice" class="mt-8">
        <.input
          type="radios"
          id="letters-choice-input"
          name="choice"
          label="For the checked members"
          value={@choice}
          options={choices(@checked)}
        />
      </div>
      <.action_bar id="letters-bar" hint={bar_hint(@checked, @choice)}>
        <.button
          id="letters-apply"
          variant={variant(@choice)}
          disabled={@fit == []}
          phx-disable-with={waiting(@choice)}
          {confirm(@choice, @fit, @filter_options.year, @current_team)}
        >
          {button_text(@choice, length(@fit))}
        </.button>
      </.action_bar>
    </.form>
    """
  end

  # Whether a choice reaches a checked row: Send letters a member with hours and no
  # letter, Email letters a letter whose member has an email and isn't already emailing,
  # Publish again a letter out of date.
  defp fits?("send", record), do: is_nil(record.tax_credit_letter_id) and record.total_minutes > 0

  defp fits?("email", record),
    do:
      record.tax_credit_letter_id != nil and
        record.letter_email_state not in [:no_email, :sending]

  defp fits?("publish", record), do: record.letter_hours_status == :changed
  defp fits?(_choice, _record), do: false

  # Each choice with what it does for the checked, or greyed with why it reaches nobody.
  defp choices(checked) do
    for choice <- @choices do
      fit = Enum.count(checked, &fits?(choice, &1))

      cond do
        checked == [] -> {choice_label(choice), choice, hint(choice, nil)}
        fit == 0 -> {choice_label(choice), choice, none(choice, length(checked)), disabled: true}
        true -> {choice_label(choice), choice, hint(choice, fit)}
      end
    end
  end

  defp choice_label("send"), do: "Send letters"
  defp choice_label("email"), do: "Email letters"
  defp choice_label("publish"), do: "Publish again"

  defp hint("send", nil),
    do: "Creates and emails a letter to each checked member with hours and no letter."

  defp hint("email", nil), do: "Emails their letter again to each checked member with one."

  defp hint("publish", nil),
    do: "Prints a new letter for each checked member out of date, and emails it."

  defp hint("send", n), do: "Creates and emails a letter to #{the_checked(n)} with no letter."
  defp hint("email", n), do: "Emails their letter again to #{the_checked(n)} with one."

  defp hint("publish", n),
    do: "Prints a new letter for #{the_checked(n)} out of date, and emails it."

  defp none("send", n), do: "#{none_of(n)} is without a letter and has hours."
  defp none("email", n), do: "#{none_of(n)} has a letter to email."
  defp none("publish", n), do: "#{none_of(n)} is out of date."

  defp the_checked(n), do: Service.Format.count(n, one: "the %d checked", many: "the %d checked")
  defp none_of(1), do: "The member checked"
  defp none_of(n), do: "None of the #{n} checked"

  defp letters(n), do: Service.Format.count(n, one: "%d letter", many: "%d letters")

  defp button_text("send", n) when n > 0, do: "Send #{letters(n)}"
  defp button_text("email", n) when n > 0, do: "Email #{letters(n)}"
  defp button_text("publish", n) when n > 0, do: "Publish #{letters(n)} again"
  defp button_text(_choice, _n), do: "Change letters"

  defp variant("send"), do: :success
  defp variant(_choice), do: :primary

  defp waiting("publish"), do: "Publishing…"
  defp waiting(_choice), do: "Sending…"

  # What to do next while the button is greyed: check someone, then pick a choice.
  defp bar_hint([], _choice), do: "Check members, then select what to do."
  defp bar_hint(_checked, nil), do: "Select what to do."
  defp bar_hint(_checked, _choice), do: nil

  # Each confirm counts who gets an email, so it leaves out the members with no email.
  defp confirm(_choice, [], _year, _team), do: %{}

  defp confirm("send", fit, year, team) do
    unsigned = if team.signature, do: [], else: ["They go out unsigned."]

    send_confirm(
      emailed(fit),
      "Create and email #{letters(length(fit))} for #{year}?",
      ["Each member checked with hours and no letter gets one." | unsigned] ++ not_emailed(fit)
    )
  end

  defp confirm("email", fit, _year, _team),
    do:
      send_confirm(length(fit), "Email #{letters(length(fit))} again?", [
        "Each member checked gets the letter they have, as it was published."
      ])

  defp confirm("publish", fit, _year, _team) do
    fit
    |> emailed()
    |> send_confirm("Publish #{letters(length(fit))} again?", [
      "Each gets a new ID, and the old one's verify page says Replaced.",
      "Each new letter is emailed to its member." | not_emailed(fit)
    ])
    |> Map.put("data-confirm-button", "Publish again")
  end

  defp confirm(_choice, _fit, _year, _team), do: %{}

  defp emailed(records), do: Enum.count(records, &CreateTaxCreditLetters.emailed?(&1.member))

  defp not_emailed(records) do
    case records
         |> Enum.reject(&CreateTaxCreditLetters.emailed?(&1.member))
         |> Enum.map(& &1.member.name) do
      [] -> []
      names -> ["No email, so not emailed: #{Service.Format.and_list(Enum.sort(names))}."]
    end
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

  # The checked members and the choice, kept so a re-render never unchecks them.
  def handle_event("tick", params, socket),
    do: {:noreply, socket |> assign_ticks(params) |> assign_checked()}

  def handle_event("apply", params, socket) do
    socket = socket |> assign_ticks(params) |> assign_checked()

    case socket.assigns do
      %{fit: []} ->
        {:noreply, put_flash(socket, :error, "Check members, then select what to do.")}

      %{choice: choice, fit: fit} ->
        {:noreply, apply_choice(socket, choice, fit)}
    end
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

  defp apply_choice(socket, "send", fit) do
    %{current_team: team, current_user: user, filter_options: %{year: year}} = socket.assigns
    CreateTaxCreditLettersWorker.enqueue(team, year, Enum.map(fit, & &1.member.id), user)
    socket |> clear_ticks() |> assign(sending: %{count: length(fit), year: year}, sent: nil)
  end

  defp apply_choice(socket, "email", fit) do
    letters =
      socket.assigns.current_team
      |> TaxCreditLetter.get_all_current(Enum.map(fit, & &1.tax_credit_letter_id))
      |> CreateTaxCreditLetters.email_again()

    socket
    |> clear_ticks()
    |> assign_records()
    |> put_flash(
      :info,
      "Emailing #{letters(length(letters))} again. Each row updates as it goes."
    )
  end

  # Each prints a PDF, so they publish in the background and the page stays live.
  defp apply_choice(socket, "publish", fit) do
    %{current_team: team, current_user: user, filter_options: %{year: year}} = socket.assigns
    rows = for record <- fit, do: {record.member.id, record.tax_credit_letter_id}

    socket
    |> clear_ticks()
    |> assign(publishing: length(rows))
    |> start_async(:publish_again, fn ->
      CreateTaxCreditLetters.publish_again(team, year, rows, user)
    end)
  end

  def handle_async(:publish_again, {:ok, %{published: published, stale: stale}}, socket) do
    socket = socket |> assign(publishing: nil) |> assign_records()
    done = "Published #{letters(length(published))} again."

    if stale == 0,
      do: {:noreply, put_flash(socket, :info, done)},
      else:
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{done} #{Service.Format.count(stale, one: "%d was", many: "%d were")} published by someone else meanwhile."
         )}
  end

  def handle_async(:publish_again, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(publishing: nil)
     |> assign_records()
     |> put_flash(:error, "Publishing again stopped. Check the list, then try again.")}
  end

  # Ids come from the browser; only rows shown are checked.
  defp assign_ticks(socket, params) do
    ids =
      params
      |> Map.get("member_ids", [])
      |> Enum.flat_map(fn id ->
        case Integer.parse(id) do
          {id, ""} -> [id]
          _other -> []
        end
      end)

    choice = if params["choice"] in @choices, do: params["choice"]
    assign(socket, selected: MapSet.new(ids), choice: choice)
  end

  defp clear_ticks(socket), do: socket |> assign(selected: MapSet.new()) |> assign_checked()

  # The checked rows among those shown, and those the choice reaches.
  defp assign_checked(socket) do
    %{records: records, selected: selected, choice: choice} = socket.assigns
    checked = Enum.filter(records, &MapSet.member?(selected, &1.member.id))

    assign(socket,
      selected: MapSet.new(checked, & &1.member.id),
      checked: checked,
      fit: Enum.filter(checked, &fits?(choice, &1))
    )
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
    |> assign_checked()
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
end
