defmodule Web.ActivityOrgFormLive do
  @moduledoc """
  An organization's form on an activity (#950), for team admins only: what SAR Duty
  filled in, what's missing with the page that fixes it, and the questions, with a row
  for each person a form asks about, such as On task, and their total, and each
  equipment use's total for a form that works one out. Answers save as
  they change (App.Operation.SaveFormAnswers), and each row's total follows them. Download draft PDF posts the form to
  Web.ActivityFormPDFController, which keeps the answers and sends a draft PDF, never saved.

  A form that's on publishes (#970, App.Operation.PublishDocument). The Published box
  above the answers says when and who, with Download, the verify link, and Withdraw.
  When the form reads differently now, it says what changed and offers Publish again.

  The form is found on for the team's organization, and the activity through the team,
  so another organization's form, one turned off, or one not for this activity is a 404.
  """
  use Web, :live_view_app_layout

  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.FormAnswer
  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Operation.PublishDocument
  alias App.Operation.SaveFormAnswers
  alias App.Operation.WithdrawDocument
  alias App.ViewData.ActivityForms
  alias Web.Components.ReportTable

  def mount(%{"id" => id, "form_id" => form_id}, _session, socket) do
    team = socket.assigns.current_team
    activity = team |> Activity.find!(id) |> App.Repo.preload(:team)
    if activity.deleted_at, do: raise(Web.Status.NotFound)
    form = Form.get_shown(team, form_id) || raise(Web.Status.NotFound)

    socket =
      assign(socket,
        page_title: "#{form.name} for #{activity.title}",
        activity: activity,
        form: form,
        errors: %{}
      )

    case ActivityForms.load(team, activity, form, DateTime.utc_now()) do
      {:ok, page} ->
        socket = assign(socket, page: page, problem: nil, answers: page.answers, rows: page.rows)
        {:ok, assign_published(socket)}

      {:error, :not_shown} ->
        raise Web.Status.NotFound

      {:error, reason} ->
        {:ok,
         socket
         |> assign(page: nil, problem: reason, answers: %{}, rows: [])
         |> assign_published()}
    end
  end

  # The form's PDFs for the activity, and what changed since the current one.
  defp assign_published(socket) do
    %{current_team: team, activity: activity, form: form, page: page} = socket.assigns
    published = ActivityForms.published(team, activity, form)

    changes =
      if published.current && page,
        do:
          ActivityForms.changes(
            page,
            FormAnswer.starting(activity, page.doc.asks),
            published.current
          ),
        else: []

    # Who published it, by their member name, as other "by" lines say.
    published_by =
      published.current &&
        Member.name_for_user(team, published.current.user, DateTime.utc_now())

    assign(socket, published: published, changes: changes, published_by: published_by)
  end

  # Each change saves the answers that read, and shows what's wrong with the rest. What
  # was typed stays in the boxes either way, and each row's total follows what reads.
  def handle_event("change", %{"answers" => typed}, %{assigns: %{page: %{}}} = socket) do
    %{activity: activity, page: page, current_user: user} = socket.assigns

    errors =
      case SaveFormAnswers.call(activity, page.doc, typed, user) do
        {:ok, _answers} -> %{}
        {:error, errors} -> errors
      end

    answers = Map.merge(socket.assigns.answers, typed)
    rows = ActivityForms.rows(page.doc, page.values, answers, page.timezone)

    {:noreply,
     socket |> assign(answers: answers, rows: rows, errors: errors) |> assign_published()}
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  # A box that shows an error isn't saved, so publishing then would print its last saved
  # answer, not what the box shows.
  def handle_event("publish", _params, %{assigns: %{errors: errors}} = socket)
      when errors != %{} do
    {:noreply, put_flash(socket, :error, fix_first())}
  end

  def handle_event("publish", _params, socket) do
    %{current_team: team, form: form, activity: activity, current_user: user} = socket.assigns
    current = socket.assigns.published.current

    case PublishDocument.call(
           team,
           form,
           activity,
           user,
           current && current.id,
           DateTime.utc_now()
         ) do
      {:ok, pdf} ->
        socket =
          socket
          |> assign_published()
          |> put_flash(:info, "Published #{form.name}, #{code(pdf)}.")

        {:noreply, socket}

      {:error, message} ->
        {:noreply, socket |> assign_published() |> put_flash(:error, message)}
    end
  end

  def handle_event("withdraw", _params, socket) do
    %{current_team: team, current_user: user, published: %{current: pdf}} = socket.assigns

    case pdf && WithdrawDocument.call(team, pdf, user, DateTime.utc_now()) do
      {:ok, pdf} ->
        {:noreply, socket |> assign_published() |> put_flash(:info, "Withdrew #{code(pdf)}.")}

      {:error, message} ->
        {:noreply, socket |> assign_published() |> put_flash(:error, message)}

      nil ->
        {:noreply, assign_published(socket)}
    end
  end

  defp code(pdf), do: PublishedPDF.format_code(pdf.code)

  defp fix_first, do: "Fix the boxes marked first. Publish prints what's saved."

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={@activity.ref_id || @activity.title}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label={@form.name} />
    </.breadcrumbs>
    <.banner
      :if={@form.state == :testing}
      id="org-form-in-development"
      kind={:warning}
      title="Testing only"
      class="mb-6"
    >
      <p>This form is testing and not ready for real use. Don't send what it prints.</p>
    </.banner>
    <h1 class="title">{@page_title}</h1>
    <p :if={@form.about} class="lead measure">{@form.about}</p>

    <.banner :if={@problem} id="org-form-problem" kind={:danger} title="This form cannot print">
      <p>{@problem}</p>
      <p>Ask for help with Get help.</p>
    </.banner>

    <div :if={@page} class="measure">
      <.published_box
        published={@published}
        published_by={@published_by}
        changes={@changes}
        errors={@errors}
        form={@form}
        team={@current_team}
      />

      <section :if={@page.missing != []} id="org-form-missing" class="mb-8">
        <h2 class="heading">Missing</h2>
        <p class="mb-4">
          {Service.Format.count(length(@page.missing),
            one: "%d value this form reads is empty. Fill it in, and every form gets it.",
            many: "%d values this form reads are empty. Fill them in, and every form gets them."
          )} The PDF still prints with blanks.
        </p>
        <.read_table id="org-form-missing-table" rows={@page.missing} team={@current_team}>
          <:value :let={row}>
            <.badge kind={:warning}>Missing</.badge>
            <.a
              :if={fix = fix(row, @activity)}
              id={"org-form-fix-#{row_id(row)}"}
              class="ml-2"
              navigate={fix.path}
            >{fix.label}</.a>
          </:value>
        </.read_table>
      </section>

      <section :if={@page.filled != []} id="org-form-filled" class="mb-8">
        <h2 class="heading">Filled in by SAR Duty</h2>
        <.read_table id="org-form-filled-table" rows={@page.filled} team={@current_team}>
          <:value :let={row}>{ReportTable.value_text(row.value, row.column, @current_team)}</:value>
        </.read_table>
      </section>

      <.form
        for={%{}}
        as={:answers}
        id="org-form-answers"
        action={~p"/teams/#{@current_team}/activities/#{@activity.id}/forms/#{@form.id}/pdf"}
        method="post"
        phx-change="change"
      >
        <%!-- Enter in a box would download a PDF: a disabled first button stops it. --%>
        <button type="submit" disabled hidden aria-hidden="true"></button>
        <section :if={ActivityForms.questions(@page.doc) != []} id="org-form-questions" class="mb-8">
          <h2 class="heading">Questions</h2>
          <p class="hint mb-4">
            Your answers stay with this activity. Another form that asks the same thing starts from them.
          </p>
          <.ask
            :for={ask <- ActivityForms.questions(@page.doc)}
            ask={ask}
            type={App.Document.ask_type(@page.doc, ask)}
            value={@answers[ask.name]}
            errors={List.wrap(@errors[ask.name])}
          />
        </section>
        <.rows_table
          :for={table <- @rows}
          table={table}
          doc={@page.doc}
          team={@current_team}
          errors={@errors}
        />
        <p :if={@form.state == :on} class="hint">
          A draft says DRAFT on every page and is never kept. Publish keeps the PDF, with an ID
          anyone holding it can check.
        </p>
        <p
          :if={@form.state == :on and @errors != %{}}
          id="org-form-fix-first"
          class="text-danger-text"
        >
          {fix_first()}
        </p>
        <.form_actions>
          <.button
            :if={@form.state == :on and is_nil(@published.current)}
            id="org-form-publish"
            type="button"
            variant={:primary}
            phx-click="publish"
            phx-disable-with="Publishing…"
            disabled={@errors != %{}}
          >
            Publish
          </.button>
          <.button
            id="org-form-download"
            type="submit"
            variant={if @form.state == :on, do: :secondary, else: :primary}
          >
            Download draft PDF
          </.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  attr :published, :map, required: true
  attr :published_by, :string, default: nil
  attr :changes, :list, required: true
  attr :errors, :map, required: true
  attr :form, :map, required: true
  attr :team, :map, required: true

  # The current PDF: when and who, Download, the verify link, Withdraw, and Publish again
  # with what changed when it's out of date. Earlier ones under it, marked.
  defp published_box(assigns) do
    ~H"""
    <section
      :if={@published.current || @published.earlier != []}
      id="org-form-published"
      class="mb-8"
    >
      <h2 class="heading">Published</h2>
      <div :if={pdf = @published.current} id="org-form-current" class="card">
        <p class="mb-2">
          {Service.Format.datetime_short(pdf.inserted_at, @team.timezone)}
          <span :if={@published_by}>by {@published_by}</span>
        </p>
        <p class="mono mb-4">
          <.a id="org-form-verify" href={PublishedPDF.verify_link(pdf.code)} external>{PublishedPDF.format_code(
            pdf.code
          )}</.a>
        </p>
        <div :if={@changes != []} id="org-form-out-of-date" class="callout mb-4">
          <p class="mb-1"><b>Out of date.</b> The form reads differently now:</p>
          <ul>
            <li :for={change <- @changes}>{change}</li>
          </ul>
        </div>
        <.form_actions>
          <.button
            id="org-form-download-published"
            href={~p"/teams/#{@team}/pdfs/#{pdf.id}"}
            variant={:primary}
          >
            Download PDF
          </.button>
          <.button
            :if={@form.state == :on}
            id="org-form-publish-again"
            type="button"
            variant={if @changes != [], do: :warning, else: :secondary}
            phx-click="publish"
            phx-disable-with="Publishing…"
            disabled={@errors != %{}}
            data-confirm={"Publish #{@form.name} again? It gets a new ID."}
            data-confirm-warning={"The verify page for #{PublishedPDF.format_code(pdf.code)} will say Replaced."}
            data-confirm-button="Publish again"
          >
            Publish again
          </.button>
          <:trailing>
            <.button
              id="org-form-withdraw"
              type="button"
              variant={:danger}
              phx-click="withdraw"
              phx-disable-with="Withdrawing…"
              data-confirm={"Withdraw #{PublishedPDF.format_code(pdf.code)}? Nothing takes its place."}
              data-confirm-warning="Its verify page will say Withdrawn."
              data-confirm-check="I understand anyone holding it will see it was withdrawn."
              data-confirm-button="Withdraw"
            >
              Withdraw
            </.button>
          </:trailing>
        </.form_actions>
      </div>

      <ul :if={@published.earlier != []} id="org-form-earlier" class="value-rows mt-4 text-sm">
        <li :for={pdf <- @published.earlier} id={"org-form-earlier-#{pdf.id}"}>
          <span>
            <.a href={~p"/teams/#{@team}/pdfs/#{pdf.id}"} target="_blank" class="mono">{PublishedPDF.format_code(
              pdf.code
            )}</.a>
            <span class="hint">
              {Service.Format.date_long(pdf.inserted_at, @team.timezone)}
            </span>
          </span>
          <.badge :if={PublishedPDF.status(pdf) == :replaced} kind={:warning}>Replaced</.badge>
          <.badge :if={PublishedPDF.status(pdf) == :withdrawn} kind={:danger}>Withdrawn</.badge>
        </li>
      </ul>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :team, :map, required: true
  slot :value, required: true

  # Each value the form reads beside its field's name, as an activity's Fields tab shows
  # them.
  defp read_table(assigns) do
    ~H"""
    <div class="table-wrap">
      <table id={@id} class="table table-striped table-fields">
        <tbody>
          <tr :for={row <- @rows} id={"#{@id}-#{row_id(row)}"}>
            <th scope="row">{row.label}</th>
            <td>{render_slot(@value, row)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :table, :map, required: true, doc: "one of ActivityForms.rows/4's"
  attr :doc, :map, required: true
  attr :team, :map, required: true
  attr :errors, :map, required: true

  # A row for each person or item the form asks about or works a total out for, with a
  # box for each answer and the row's total. A blank box takes the answer shown in grey.
  defp rows_table(assigns) do
    ~H"""
    <section id={"org-form-rows-#{@table.report}"} class="mb-8">
      <h2 class="heading">{String.capitalize(@table.report)}</h2>
      <p :for={hint <- blank_hints(@table.asks, @doc.asks)} class="hint mb-4">{hint}</p>
      <.table
        id={"org-form-rows-#{@table.report}-table"}
        rows={@table.rows}
        row_id={&"org-form-row-#{&1.dom}"}
        class="table-striped"
      >
        <:col :let={row} :if={@table.kind == :member} label="Member">
          <.member_cell member={%{id: row.id, name: row.name}} team={@team} />
        </:col>
        <:col :let={row} :if={@table.kind == :item} label="Item">
          <.item_cell item={%{title: row.name}} link={false} status={false} />
        </:col>
        <:col :let={row} :for={ask <- @table.asks} label={ask.label} class="w-px whitespace-nowrap">
          <.row_answer
            ask={ask}
            row={row}
            type={App.Document.ask_type(@doc, ask)}
            error={@errors |> Map.get(ask.name) |> row_error(row.key)}
          />
        </:col>
        <:col
          :let={row}
          :if={@table.total}
          label={@table.total}
          align="right"
          class="w-px whitespace-nowrap"
        >
          <span id={"org-form-total-#{row.dom}"}>{row.total}</span>
        </:col>
      </.table>
    </section>
    """
  end

  attr :ask, :map, required: true
  attr :row, :map, required: true
  attr :type, :atom, required: true
  attr :error, :string, default: nil

  defp row_answer(%{ask: %{choices: [_ | _]}} = assigns) do
    ~H"""
    <select
      id={"org-form-answer-#{@ask.name}-#{dom_key(@row.key)}"}
      name={"answers[#{@ask.name}][#{@row.key}]"}
      class={["w-auto", @error && "is-invalid"]}
      aria-label={"#{@ask.label} for #{@row.name}"}
    >
      {Phoenix.HTML.Form.options_for_select(
        @ask.choices,
        @row.answers[@ask.name] || @row.defaults[@ask.name]
      )}
    </select>
    <.error :if={@error}>{@error}</.error>
    """
  end

  defp row_answer(assigns) do
    ~H"""
    <input
      type={input_type(@type)}
      id={"org-form-answer-#{@ask.name}-#{dom_key(@row.key)}"}
      name={"answers[#{@ask.name}][#{@row.key}]"}
      value={@row.answers[@ask.name]}
      placeholder={@row.defaults[@ask.name]}
      step={@type == :number && "any"}
      min={@type == :number && "0"}
      class={[@type == :number && "w-16", @error && "is-invalid"]}
      aria-label={"#{@ask.label} for #{@row.name}"}
      phx-debounce="blur"
    />
    <.error :if={@error}>{@error}</.error>
    """
  end

  # A row's answer that starts from another answer: blank, it takes that one.
  defp blank_hints(asks, all) do
    for %{default: {:value, name, _line}} = ask <- asks,
        other = Enum.find(all, &(&1.name == name)),
        do: "Leave #{ask.label} blank to use #{other.label}."
  end

  defp row_error(errors, key) when is_map(errors), do: errors[key]
  defp row_error(_message, _key), do: nil

  defp dom_key(key), do: String.replace(key || "", ":", "-")

  attr :ask, :map, required: true
  attr :type, :atom, default: :text
  attr :value, :any, default: nil
  attr :errors, :list, default: []

  defp ask(%{ask: %{choices: [_ | _] = choices}} = assigns) do
    assigns = assign(assigns, options: Enum.map(choices, &{&1, &1}))

    ~H"""
    <.input
      id={"org-form-answer-#{@ask.name}"}
      name={"answers[#{@ask.name}]"}
      type="radios"
      label={@ask.label}
      options={@options}
      value={@value}
      errors={@errors}
    >
      {@ask.hint}
    </.input>
    """
  end

  defp ask(assigns) do
    ~H"""
    <.input
      id={"org-form-answer-#{@ask.name}"}
      name={"answers[#{@ask.name}]"}
      type={input_type(@type)}
      label={@ask.label}
      value={@value}
      errors={@errors}
      step={@type == :number && "any"}
      phx-debounce="blur"
    >
      {@ask.hint}
    </.input>
    """
  end

  defp input_type(:number), do: "number"
  defp input_type(:day), do: "date"
  defp input_type(_text), do: "text"

  defp row_id(row), do: row.name |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-")

  # The page that fixes an empty value, so the fix reaches D4H and every form: an
  # activity's D4H field on Change fields, its own details on Change activity, and the
  # team's on team settings: its names on General, and its address and signer beside
  # its tax credit letters'. Anything else has no page here.
  defp fix(%{from: "activities", custom?: true}, activity),
    do: %{
      label: "Change fields",
      path: ~p"/teams/#{activity.team}/activities/#{activity.id}/fields/edit"
    }

  defp fix(%{from: "activities"}, activity),
    do: %{
      label: "Change activity",
      path: ~p"/teams/#{activity.team}/activities/#{activity.id}/edit"
    }

  defp fix(%{from: "team", name: name}, activity) when name in ~w(team.name team.legal_name),
    do: %{label: "Team settings", path: ~p"/teams/#{activity.team}/settings"}

  defp fix(%{from: "team"}, activity),
    do: %{
      label: "Team settings",
      path: ~p"/teams/#{activity.team}/settings/tax-credit-letters"
    }

  defp fix(_row, _activity), do: nil
end
