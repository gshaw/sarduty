defmodule Web.Components.PublishedPDF do
  @moduledoc """
  The parts a published PDF's page shares, a letter's and a form's (#970, #995): the
  warning banners Out of date and Needed to publish, under the page's title, page 1 as
  a picture, History, and Withdraw's confirm.
  """
  use Web, :function_component

  import Web.Components.A
  import Web.Components.Table

  alias App.Adapter.D4H
  alias App.Model.PublishedPDF
  alias App.Operation.ReadDocument
  alias Web.Components.TeamSettingsTabs

  attr :id, :string, required: true
  attr :noun, :string, required: true, doc: "what reads differently: \"letter\", \"form\""

  attr :changes, :list,
    required: true,
    doc: "a line for each value its verify page would show otherwise"

  attr :next, :string,
    default: nil,
    doc: "what its button does: \"Publish again makes a new one.\""

  # What its verify page would show differently if it were published today (#995).
  def out_of_date(assigns) do
    ~H"""
    <.banner :if={@changes != []} id={@id} kind={:warning} title="Out of date" class="measure">
      <p>Published today, this {@noun} would read:</p>
      <ul>
        <li :for={change <- @changes}>{change}</li>
      </ul>
      <p :if={@next}>{@next}</p>
    </.banner>
    """
  end

  attr :id, :string, required: true

  attr :what, :string,
    required: true,
    doc: "what can't be published: \"This letter\", \"Letters\""

  attr :needed, :list, required: true, doc: "App.Operation.ReadDocument.needed/3's"
  attr :team, :map, required: true
  attr :activity, :map, default: nil, doc: "a form's, whose fields fill it"

  attr :action, :atom,
    default: :publish,
    values: [:publish, :email],
    doc: "what its button does: a letter's Email says emailed (#995)"

  # What publishing needs that's missing, each with the page that fills it, or what the
  # activity has to do first (#995). The same words as publishing's refusal.
  def needed_banner(%{needed: [one]} = assigns) do
    assigns = assign(assigns, one: one, verb: verb(assigns.action))

    ~H"""
    <.banner id={@id} kind={:warning} title={title(@action)} class="measure">
      <p>{ReadDocument.needed_error(@what, [@one], @verb)}</p>
      <.need_fix id={"#{@id}-fix"} need={@one} team={@team} activity={@activity} sentence />
    </.banner>
    """
  end

  def needed_banner(%{needed: [_, _ | _]} = assigns) do
    assigns = assign(assigns, verb: verb(assigns.action))

    ~H"""
    <.banner id={@id} kind={:warning} title={title(@action)} class="measure">
      <p :if={Enum.all?(@needed, &is_nil(ReadDocument.waits_for(&1)))}>
        {@what} cannot be {@verb} without {length(@needed)} values:
      </p>
      <p :if={Enum.any?(@needed, &ReadDocument.waits_for/1)}>
        {@what} needs {length(@needed)} things before it can be {@verb}:
      </p>
      <ul>
        <li :for={need <- @needed}><.need_fix need={need} team={@team} activity={@activity} /></li>
      </ul>
    </.banner>
    """
  end

  def needed_banner(assigns), do: ~H""

  defp title(:publish), do: "Needed to publish"
  defp title(:email), do: "Needed to email"

  @doc "The word a refusal uses for `action`: a letter is emailed, a form published."
  def verb(:publish), do: "published"
  def verb(:email), do: "emailed"

  attr :id, :string, default: nil
  attr :need, :map, required: true
  attr :team, :map, required: true
  attr :activity, :map, default: nil
  attr :sentence, :boolean, default: false, doc: "its own sentence, not after its label"

  # How to fill one need: a sentence of its own, or a list line after its label.
  defp need_fix(assigns) do
    parts = fix_parts(assigns)
    lead = if assigns.sentence, do: "", else: assigns.need.label <> if(parts, do: ": ", else: "")
    assigns = assign(assigns, parts: parts || %{before: "", link: nil, after: ""}, lead: lead)

    ~H"""
    <p :if={@sentence and @parts.before != ""}>
      {@parts.before}<.link_part id={@id} link={@parts.link} />{@parts.after}
    </p>
    <span :if={!@sentence}>{@lead}{@parts.before}<.link_part link={@parts.link} />{@parts.after}</span>
    """
  end

  attr :id, :string, default: nil
  attr :link, :any, required: true, doc: "`{text, path}`, or nil"

  defp link_part(%{link: nil} = assigns), do: ~H""

  defp link_part(assigns) do
    ~H"""
    <.a id={@id} navigate={elem(@link, 1)}>{elem(@link, 0)}</.a>
    """
  end

  # The page that fills a value, or what the activity has to do. Publishing an activity
  # is D4H's step, so it names the service and links the activity's page, which opens
  # it there; finishing needs only time, so it says when.
  defp fix_parts(%{need: need, team: team, activity: activity, sentence: sentence}) do
    stop = if sentence, do: ".", else: ""

    case {ReadDocument.waits_for(need), activity, fix(need, team, activity)} do
      {:published, %{} = activity, _fix} ->
        %{
          before: if(sentence, do: "Publish ", else: "publish "),
          link: {"the activity", ~p"/teams/#{team}/activities/#{activity.id}"},
          after: " in #{D4H.service_name(team)}#{stop}"
        }

      {:finished, %{} = activity, _fix} ->
        finishes = Service.Format.datetime_short(activity.finished_at, team.timezone)

        %{
          before: "#{if sentence, do: "It", else: "the activity"} finishes #{finishes}#{stop}",
          link: nil,
          after: ""
        }

      {nil, _activity, %{} = fix} ->
        %{
          before: "#{if sentence, do: String.capitalize(fix.how), else: fix.how} ",
          link: {fix.in_text, fix.path},
          after: stop
        }

      _none ->
        nil
    end
  end

  @doc """
  Where to fill in a value a letter or form reads (#950, #995), so the fix reaches D4H
  and every letter and form: `%{label, in_text, how, path}`, or nil for one no page
  here fills. An answer is filled under Questions, an activity's D4H field on Change
  fields, its own details on Change activity, and the team's in team settings, on the
  tab that has it. `label` names the page as a link alone, `in_text` mid-sentence.
  """
  def fix(%{from: :answer}, _team, _activity),
    do: %{
      label: "Questions",
      in_text: "Questions",
      how: "answer it under",
      path: "#org-form-questions"
    }

  def fix(%{from: "activities", custom?: true}, team, %{} = activity),
    do: %{
      label: "Change fields",
      in_text: "Change fields",
      how: "fill it in with",
      path: ~p"/teams/#{team}/activities/#{activity.id}/fields/edit"
    }

  def fix(%{from: "activities"}, team, %{} = activity),
    do: %{
      label: "Change activity",
      in_text: "Change activity",
      how: "fill it in with",
      path: ~p"/teams/#{team}/activities/#{activity.id}/edit"
    }

  def fix(%{from: "team", name: name}, team, _activity) do
    case TeamSettingsTabs.tab_for(name) do
      nil ->
        nil

      tab ->
        %{
          label: "Team settings",
          in_text: "team settings",
          how: "add it in",
          path: TeamSettingsTabs.tab_path(team, tab)
        }
    end
  end

  def fix(_value, _team, _activity), do: nil

  attr :prefix, :string, required: true, doc: "the page's id prefix: \"letter\", \"org-form\""
  attr :pdf, :map, required: true
  attr :published_by, :string, default: nil
  attr :team, :map, required: true
  slot :status, doc: "a line on where it went, such as a letter's email"
  slot :actions, doc: "buttons after Download PDF: Email letter, or a form's Publish again"
  slot :withdraw, doc: "Withdraw, apart on the right"

  @doc """
  The Published section, the same on a letter and a form (#995): when and who, its ID
  linking to its verify page, Download PDF, the page's own buttons, and Withdraw apart.
  Nothing in it is yellow: Out of date and Needed to publish are banners under the title.
  """
  def published_section(assigns) do
    ~H"""
    <section id={"#{@prefix}-published"} class="mb-8">
      <h2 class="heading">Published</h2>
      <div id={"#{@prefix}-current"} class="card">
        <p class="mb-2">
          {Service.Format.datetime_short(@pdf.inserted_at, @team.timezone)}
          <span :if={@published_by}>by {@published_by}</span>
        </p>
        <p class="mono mb-2">
          <.a id={"#{@prefix}-verify"} href={PublishedPDF.verify_link(@pdf.code)} external>{PublishedPDF.format_code(
            @pdf.code
          )}</.a>
        </p>
        {render_slot(@status)}
        <.form_actions class="mt-4">
          <.button
            id={"#{@prefix}-download-published"}
            href={~p"/teams/#{@team}/pdfs/#{@pdf.id}"}
            variant={:primary}
          >
            Download PDF
          </.button>
          {render_slot(@actions)}
          <:trailing>{render_slot(@withdraw)}</:trailing>
        </.form_actions>
      </div>
    </section>
    """
  end

  attr :prefix, :string, required: true
  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :open, :boolean, default: false

  @doc """
  Page 1, drawn from the PDF when the page asks (Web.PublishedPDFController.preview/2),
  under a heading that folds it: open on a letter, where nothing follows, and folded on
  a form, whose answers follow (#995).
  """
  def page_one(assigns) do
    ~H"""
    <details id={"#{@prefix}-page-1"} class="mb-8" open={@open}>
      <summary class="heading cursor-pointer">Page 1</summary>
      <img
        id={"#{@prefix}-preview"}
        src={@src}
        alt={@alt}
        loading="lazy"
        class="w-full max-w-xl mt-3 border border-border-subtle shadow-sm"
      />
    </details>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "App.ViewData.PublishedHistory.rows/2's"
  attr :team, :map, required: true

  def history(assigns) do
    ~H"""
    <section :if={@rows != []} id={@id} class="mb-8">
      <h2 class="heading">History</h2>
      <.table id={"#{@id}-table"} rows={@rows} row_id={&row_id(@id, &1)} class="table-striped">
        <:col :let={row} label="When" class="w-px whitespace-nowrap">
          {row.at && Service.Format.datetime_short(row.at, @team.timezone)}
        </:col>
        <:col :let={row} label="What">
          {what(row.what)}
          <.a href={~p"/teams/#{@team}/pdfs/#{row.pdf.id}"} target="_blank" class="mono">{PublishedPDF.format_code(
            row.pdf.code
          )}</.a>
          <.status_badge :if={row.what == :published} pdf={row.pdf} />
        </:col>
        <:col :let={row} label="By">{row.by}</:col>
      </.table>
    </section>
    """
  end

  attr :pdf, :map, required: true

  defp status_badge(assigns) do
    ~H"""
    <.badge :if={PublishedPDF.status(@pdf) == :replaced} kind={:warning}>Replaced</.badge>
    <.badge :if={PublishedPDF.status(@pdf) == :withdrawn} kind={:danger}>Withdrawn</.badge>
    """
  end

  defp what(:published), do: "Published"
  defp what(:withdrawn), do: "Withdrew"

  defp row_id(id, row), do: "#{id}-#{row.what}-#{row.pdf.id}"

  @doc """
  Withdraw's confirm, the same on every published PDF: nothing takes its place, so the
  box must be ticked. `button` is the button's words.
  """
  def withdraw_confirm(%PublishedPDF{code: code}, button) do
    code = PublishedPDF.format_code(code)

    %{
      "data-confirm" => "Withdraw #{code}? Nothing takes its place.",
      "data-confirm-warning" =>
        "Anyone holding a copy will see it was withdrawn on its verify page.",
      "data-confirm-check" => "I understand #{code} no longer verifies.",
      "data-confirm-button" => button
    }
  end
end
