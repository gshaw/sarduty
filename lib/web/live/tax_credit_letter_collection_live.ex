defmodule Web.TaxCreditLetterCollectionLive do
  @moduledoc """
  A year's tax credit letters, one row per member (#970): each name opens the member's
  letter for the year, sent or not, and Letter says where it is. A tile per to-do over
  it filters it, To email first: everyone Email would reach (#995). Team admins check
  members and act on them under it: For the checked members, Email letters or Withdraw
  letters, and one button in the action bar at the foot of the window, as on an
  activity's Members tab. Each choice counts only the checked it fits, and one that
  fits none greys out and says why. While a value every letter needs is blank, such as
  the signer's title, Email reaches only letters it sends as they are, never one it would
  publish first. The ticks are the rows shown: a filter that hides a row unchecks it.

  Email runs in a job (App.Operation.EmailTaxCreditLetters), since each new letter
  prints a PDF; each email has its own job, and each row updates as its email goes.
  Withdraw is at once. In a year that isn't over, Email is early: its hint says each
  letter has the hours so far, and its confirm waits on a box that says so.
  """
  use Web, :live_view_app_layout

  import Web.Components.ActionBar
  import Web.Components.FilterBar
  import Web.Components.PublishedPDF, only: [needed_banner: 1]
  import Web.Components.StatSwitch

  alias App.Model.Standing
  alias App.Model.TaxCreditLetter
  alias App.Operation.EmailTaxCreditLetters
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.ReadDocument
  alias App.Operation.WithdrawDocument
  alias App.ViewModel.TaxCreditLetterFilterViewModel
  alias Web.TaxCreditLetterConfirm

  @choices ~w(email withdraw)

  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(App.PubSub, EmailTaxCreditLetters.topic(team.id))

    {:ok,
     assign(socket,
       emailing: nil,
       emailed: nil,
       selected: MapSet.new(),
       choice: nil,
       # What every letter needs from team settings, such as the signer's title (#995).
       needed: PrintTaxCreditLetter.missing_settings(team, Service.Clock.utc_now())
     )}
  end

  def handle_params(params, _uri, socket) do
    case TaxCreditLetterFilterViewModel.validate(params, socket.assigns.current_team) do
      {:ok, filter_options, changeset} ->
        socket =
          socket
          |> assign(:page_title, "#{filter_options.year} tax credit letters")
          |> assign(:filter_options, filter_options)
          |> assign(:form, to_form(changeset, as: "form"))
          |> assign(:path_fn, build_path_fn(socket.assigns.current_team, filter_options))
          # A year that isn't over is early (#995): Email asks first.
          |> assign(
            :early,
            EmailTaxCreditLetters.early?(
              filter_options.year,
              socket.assigns.current_team,
              Service.Clock.utc_now()
            )
          )
          |> assign_records()

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">{@page_title}</h1>

    <.needed_banner
      id="letters-needed"
      what="Letters"
      needed={@needed}
      team={@current_team}
      action={:email}
    />
    <.emailed_banner :if={@emailed} emailed={@emailed} />
    <.banner :if={@emailing} id="letters-emailing" title="Emailing letters" role="status">
      <p>
        Emailing {Service.Format.count(@emailing.count,
          one: "%d tax credit letter",
          many: "%d tax credit letters"
        )} for {@emailing.year}, publishing any missing or out of date first. This page updates
        when they are done.
      </p>
    </.banner>

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
        default={Integer.to_string(TaxCreditLetterFilterViewModel.default_year(@current_team))}
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
      <div id="letters-choice" class="mt-8 mb-6">
        <.input
          type="radios"
          id="letters-choice-input"
          name="choice"
          label="For the checked members"
          value={@choice}
          options={choices(@checked, %{needed: @needed, early: if(@early, do: @filter_options.year)})}
        />
      </div>
      <.action_bar id="letters-bar" hint={bar_hint(@checked, @choice)}>
        <.button
          id="letters-apply"
          variant={variant(@choice)}
          disabled={@fit == []}
          phx-disable-with={waiting(@choice)}
          {confirm(@choice, @fit, @filter_options.year, @early)}
        >
          {button_text(@choice, @fit)}
        </.button>
      </.action_bar>
    </.form>
    """
  end

  # Whether a choice reaches a checked row: Email a member it does something for
  # (EmailTaxCreditLetters.what/1), but while a value every letter needs is blank, not
  # one whose letter it would publish first. Withdraw a member with a letter.
  defp fits?("email", %{email: nil}, _needed), do: false
  defp fits?("email", record, needed), do: needed == [] or not publishes?(record)
  defp fits?("withdraw", record, _needed), do: record.tax_credit_letter_id != nil
  defp fits?(_choice, _record, _needed), do: false

  defp publishes?(record), do: EmailTaxCreditLetters.publishes?(record.email)

  # Each choice with what it does for the checked, or greyed with why it reaches nobody.
  # `context` has what every letter needs from team settings, and `early`, the year when
  # it isn't over.
  defp choices(checked, context), do: Enum.map(@choices, &choice(&1, checked, context))

  defp choice(choice, checked, %{needed: needed} = context) do
    fit = Enum.filter(checked, &fits?(choice, &1, needed))

    cond do
      checked == [] ->
        {choice_label(choice), choice, choice_hint(choice, context)}

      fit == [] ->
        {choice_label(choice), choice, none(choice, checked, needed), disabled: true}

      true ->
        {choice_label(choice), choice, choice_hint(choice, fit, checked, context)}
    end
  end

  defp choice_label("email"), do: "Email letters"
  defp choice_label("withdraw"), do: "Withdraw letters"

  defp choice_hint("email", %{early: early}),
    do: "Emails each checked member their latest letter#{what_email_does(early)}"

  defp choice_hint("withdraw", _context),
    do: "Withdraws the letter of each checked member with one. Nothing takes their place."

  defp choice_hint("email", fit, checked, %{needed: needed, early: early}) do
    {emailed, not_emailed} = Enum.split_with(fit, &EmailTaxCreditLetters.emailed?(&1.member))

    [
      emailed != [] &&
        "Emails #{the_checked(length(emailed))} their latest letter#{what_email_does(early)}",
      not_emailed != [] &&
        count_of(not_emailed,
          one: "1 with no email gets theirs on Your membership only.",
          many: "%d with no email get theirs on Your membership only."
        ),
      skipped(checked -- fit, needed)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp choice_hint("withdraw", fit, checked, _context) do
    without = length(checked) - length(fit)

    "Withdraws the #{if length(fit) == 1, do: "letter", else: "letters"} of #{the_checked(length(fit))} with one. " <>
      "Nothing takes #{if length(fit) == 1, do: "its", else: "their"} place." <>
      if(without > 0,
        do:
          " " <>
            Service.Format.count(without, one: "1 has no letter.", many: "%d have no letter."),
        else: ""
      )
  end

  # The rest of Email's hint: what it publishes first, or, in a year that isn't over,
  # that its letters have the hours so far and it asks first.
  defp what_email_does(nil), do: ". A missing or out-of-date letter is published first."

  defp what_email_does(year),
    do: ", with their hours so far. #{year} isn't over, so it asks first."

  # Who Email leaves out of the checked, and why.
  defp skipped([], _needed), do: nil

  defp skipped(records, needed) do
    {no_hours, rest} = Enum.split_with(records, &(&1.total_minutes == 0))
    {new, rest} = Enum.split_with(rest, &publishes?/1)

    [skip(:no_hours, no_hours, needed), skip(:new, new, needed), skip(:no_email, rest, needed)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp skip(_why, [], _needed), do: nil

  defp skip(:no_hours, records, _needed),
    do: count_of(records, one: "1 has no hours.", many: "%d have no hours.")

  defp skip(:new, records, needed),
    do:
      count_of(records, one: "1 needs a new letter first.", many: "%d need a new letter first.") <>
        " " <> ReadDocument.needed_error("New letters", needed)

  defp skip(:no_email, records, _needed),
    do:
      count_of(records,
        one: "1 has no email, and a letter up to date.",
        many: "%d have no email, and a letter up to date."
      )

  defp none("email", checked, needed) do
    cond do
      needed != [] and Enum.any?(checked, &publishes?/1) ->
        ReadDocument.needed_error("Letters", needed, "emailed")

      length(checked) == 1 ->
        "The member checked cannot get a letter."

      true ->
        "None of the #{length(checked)} checked can get a letter."
    end
  end

  defp none("withdraw", [_one], _needed), do: "The member checked has no letter."

  defp none("withdraw", checked, _needed),
    do: "None of the #{length(checked)} checked has a letter."

  defp the_checked(n), do: "the #{n} checked"

  defp letters(n), do: Service.Format.count(n, one: "%d letter", many: "%d letters")

  # The button counts who it reaches: the emails, or the letters published with none.
  defp button_text("email", fit) do
    case Enum.count(fit, &EmailTaxCreditLetters.emailed?(&1.member)) do
      0 when fit != [] -> "Publish #{letters(length(fit))}"
      count when count > 0 -> "Email #{letters(count)}"
      _none -> "Email letters"
    end
  end

  defp button_text("withdraw", [_ | _] = fit), do: "Withdraw #{letters(length(fit))}"
  defp button_text("withdraw", []), do: "Withdraw letters"
  defp button_text(_choice, _fit), do: "Change letters"

  defp variant("withdraw"), do: :danger
  defp variant(_choice), do: :primary

  defp waiting("withdraw"), do: "Withdrawing…"
  defp waiting(_choice), do: "Sending…"

  # What to do next while the button is greyed: check someone, then pick a choice.
  defp bar_hint([], _choice), do: "Check members, then select what to do."
  defp bar_hint(_checked, nil), do: "Select what to do."
  defp bar_hint(_checked, _choice), do: nil

  # Every Email asks, naming who gets what; Withdraw asks with its box from 1 (#995).
  defp confirm(_choice, [], _year, _early), do: %{}
  defp confirm("email", fit, year, early), do: TaxCreditLetterConfirm.email(fit, year, early)
  defp confirm("withdraw", fit, year, _early), do: TaxCreditLetterConfirm.withdraw(fit, year)
  defp confirm(_choice, _fit, _year, _early), do: %{}

  attr :emailed, :map, required: true

  defp emailed_banner(assigns) do
    ~H"""
    <.banner id="letters-emailed" kind={:success} title="Letters emailed">
      <p>
        <strong>
          {Service.Format.count(@emailed.emailing,
            one: "Emailing %d tax credit letter",
            many: "Emailing %d tax credit letters"
          )} for {@emailed.year}.
        </strong>
        {published_text(@emailed.published)}
        <span :if={@emailed.emailing > 0}>A row shows when its email fails.</span>
      </p>
      <p :if={@emailed.not_emailed != []} id="letters-not-emailed">
        No email, so on Your membership only: {Service.Format.and_list(
          Enum.map(@emailed.not_emailed, & &1.name)
        )}.
      </p>
      <p :if={@emailed.refused != []} id="letters-refused">
        {refused_text(@emailed.refused)}
      </p>
    </.banner>
    """
  end

  defp published_text(0), do: nil

  defp published_text(count),
    do:
      Service.Format.count(count, one: "1 was published first.", many: "%d were published first.")

  # The year's refusal alone, or how many a value they need kept back, and why.
  defp refused_text([{nil, message}]), do: message

  defp refused_text([{_member, message} | _rest] = refused),
    do:
      count_of(refused,
        one: "1 letter did not go out. #{message}",
        many: "%d letters did not go out. #{message}"
      )

  defp count_of(list, words), do: list |> length() |> Service.Format.count(words)

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
      :if={@record.letter_changes != []}
      id={"hours-changed-#{@record.member.id}"}
      kind={:warning}
      title={Enum.join(@record.letter_changes, ". ")}
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
    case TaxCreditLetterFilterViewModel.validate(form_params, socket.assigns.current_team) do
      {:ok, filter_options, _changeset} ->
        path = build_filter_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  defp apply_choice(socket, "email", fit), do: email(socket, fit)

  defp apply_choice(socket, "withdraw", fit) do
    %{current_team: team, current_user: user} = socket.assigns
    letters = TaxCreditLetter.get_all_current(team, Enum.map(fit, & &1.tax_credit_letter_id))
    result = WithdrawDocument.call_all(team, letters, user, Service.Clock.utc_now())
    socket |> clear_ticks() |> assign_records() |> put_withdraw_flash(result, length(fit))
  end

  defp email(socket, fit) do
    %{current_team: team, current_user: user, filter_options: %{year: year}} = socket.assigns

    ids = Enum.map(fit, & &1.member.id)

    case EmailTaxCreditLetters.call(team, year, ids, user, early: socket.assigns.early) do
      {:ok, count} ->
        socket |> clear_ticks() |> assign(emailing: %{count: count, year: year}, emailed: nil)

      {:error, message} ->
        put_flash(socket, :error, message)
    end
  end

  # Those replaced or withdrawn meanwhile, by another admin, are left as they are.
  defp put_withdraw_flash(socket, %{withdrawn: withdrawn}, checked) do
    done = "Withdrew #{letters(length(withdrawn))}."

    case checked - length(withdrawn) do
      0 ->
        put_flash(socket, :info, done)

      others ->
        put_flash(
          socket,
          :error,
          "#{done} #{Service.Format.count(others, one: "1 was", many: "%d were")} replaced or withdrawn already."
        )
    end
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
    %{records: records, selected: selected, choice: choice, needed: needed} = socket.assigns
    checked = Enum.filter(records, &MapSet.member?(selected, &1.member.id))

    assign(socket,
      selected: MapSet.new(checked, & &1.member.id),
      checked: checked,
      fit: Enum.filter(checked, &fits?(choice, &1, needed))
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
    |> assign(:standings, Standing.by_member(team, members, Service.Clock.utc_now()))
    |> assign_checked()
  end

  def handle_info({:tax_credit_letters_emailed, summary}, socket) do
    {:noreply, socket |> assign(emailing: nil, emailed: summary) |> assign_records()}
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
