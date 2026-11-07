defmodule Web.ActivityOrgFormLive do
  @moduledoc """
  An organization's form on an activity (#950), for team admins only: what SAR Duty
  filled in, what's missing with the page that fixes it, and the questions. Answers save
  as they change (App.Operation.SaveFormAnswers). Download PDF and Open PDF post the form
  to Web.ActivityFormPDFController, which keeps the answers and saves the PDF it sends.

  The form is found on for the team's organization, and the activity through the team,
  so another organization's form, one turned off, or one not for this activity is a 404.
  """
  use Web, :live_view_app_layout

  alias App.Model.Activity
  alias App.Model.Form
  alias App.Operation.SaveFormAnswers
  alias App.ViewData.ActivityForms
  alias Web.Components.ReportTable

  def mount(%{"id" => id, "form_id" => form_id}, _session, socket) do
    team = socket.assigns.current_team
    activity = team |> Activity.find!(id) |> App.Repo.preload(:team)
    if activity.deleted_at, do: raise(Web.Status.NotFound)
    form = Form.get_enabled(team, form_id) || raise(Web.Status.NotFound)

    socket =
      assign(socket,
        page_title: "#{form.name} for #{activity.title}",
        activity: activity,
        form: form,
        errors: %{}
      )

    case ActivityForms.load(team, activity, form, DateTime.utc_now()) do
      {:ok, page} ->
        {:ok, assign(socket, page: page, problem: nil, answers: page.answers)}

      {:error, :not_shown} ->
        raise Web.Status.NotFound

      {:error, reason} ->
        {:ok, assign(socket, page: nil, problem: reason, answers: %{})}
    end
  end

  # Each change saves the answers that read, and shows what's wrong with the rest. What
  # was typed stays in the boxes either way.
  def handle_event("change", %{"answers" => typed}, %{assigns: %{page: %{}}} = socket) do
    %{activity: activity, page: page, current_user: user} = socket.assigns

    errors =
      case SaveFormAnswers.call(activity, page.doc, typed, user) do
        {:ok, _answers} -> %{}
        {:error, errors} -> errors
      end

    {:noreply, assign(socket, answers: Map.merge(socket.assigns.answers, typed), errors: errors)}
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

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
    <h1 class="title">{@page_title}</h1>
    <p :if={@form.about} class="lead measure">{@form.about}</p>

    <.banner :if={@problem} id="org-form-problem" kind={:danger} title="This form cannot print">
      <p>{@problem}</p>
      <p>Ask for help with Get help.</p>
    </.banner>

    <div :if={@page} class="measure">
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
        <section :if={@page.doc.asks != []} id="org-form-questions" class="mb-8">
          <h2 class="heading">Questions</h2>
          <p class="hint mb-4">
            Your answers stay with this activity. Another form that asks the same thing starts from them.
          </p>
          <.ask
            :for={ask <- @page.doc.asks}
            ask={ask}
            type={@page.doc.types[":#{ask.name}"]}
            value={@answers[ask.name]}
            errors={List.wrap(@errors[ask.name])}
          />
        </section>
        <p class="hint">SAR Duty keeps a copy of each PDF it makes.</p>
        <.form_actions>
          <.button id="org-form-download" type="submit" variant={:primary}>Download PDF</.button>
          <.button
            id="org-form-open"
            type="submit"
            name="open"
            value="true"
            formtarget="_blank"
          >
            Open PDF
          </.button>
        </.form_actions>
      </.form>
    </div>
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
  # team's on team settings. Anything else has no page here.
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

  defp fix(%{from: "team"}, activity),
    do: %{label: "Team settings", path: ~p"/teams/#{activity.team}/settings"}

  defp fix(_row, _activity), do: nil
end
