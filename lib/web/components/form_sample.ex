defmodule Web.Components.FormSample do
  @moduledoc """
  A form drawn as pictures (#1089): tried on an activity it shows on, marked SAMPLE,
  every page a picture, or before it's written, the agency's blank page. Change form
  draws its draft with it and a form's page its saved text, the same way: on the team's
  own activities, or on Coast Range SAR's, a made-up team, for an organization's
  (App.Operation.TryForm). Each page prints it in `start_async` with `print/4` and
  answers the picker's `try_on` by printing again.
  """
  use Web, :function_component

  import Web.Components.A

  alias App.Model.Form
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.TryForm

  @doc """
  `%{activities:, activity:, pages:, preview_error:}`: `form`, with the text it has,
  tried on the activity `activity_id`, or the newest published one it shows on, on
  `page`; before it's written, `page` itself.
  """
  def print(%Form{} = form, owner, page, activity_id) do
    cond do
      Form.written?(form) -> try_on(form, owner, page, activity_id)
      page -> Map.merge(%{activities: [], activity: nil}, pages(page))
      true -> %{activities: [], activity: nil, pages: [], preview_error: nil}
    end
  end

  defp try_on(form, owner, page, activity_id) do
    activities = TryForm.activities(form, owner)
    activity = Enum.find(activities, &(&1.id == activity_id)) || TryForm.first(activities)

    printed =
      case activity && TryForm.call(form, owner, activity.id, page: page) do
        nil -> %{pages: [], preview_error: nil}
        {:ok, attachment} -> pages(attachment.content)
        {:error, reason} -> %{pages: [], preview_error: reason}
      end

    Map.merge(%{activities: activities, activity: activity}, printed)
  end

  defp pages(pdf) do
    case Service.PDFImages.pages(pdf) do
      {:ok, pages} -> %{pages: pages, preview_error: nil}
      {:error, reason} -> %{pages: [], preview_error: reason}
    end
  end

  attr :owner, :any,
    required: true,
    doc: "the team whose activities it's tried on, or an organization"

  attr :written, :boolean, required: true
  attr :activities, :list, required: true
  attr :activity, :any, required: true
  attr :pages, :list, required: true
  attr :previewing, :boolean, required: true
  attr :preview_error, :string, default: nil
  slot :blank, doc: "a line above the agency's blank page, before the form is written"

  @doc """
  The picker, the pages, and what's printing. The team's own activities, or Coast
  Range SAR's for an organization; on a team's, Open activity, at the label's end,
  checks the sample against one in a new window.
  """
  def form_sample(assigns) do
    ~H"""
    <form
      :if={@activities != []}
      id="form-try-form"
      phx-change="try_on"
      phx-submit="try_on"
      class="measure"
    >
      <div class="flex items-baseline justify-between gap-4">
        <.label for="form-try-activity">{tried_on(@owner)}</.label>
        <.a
          :if={@activity && match?(%Team{}, @owner)}
          id="form-try-open"
          href={~p"/teams/#{@owner}/activities/#{@activity.id}"}
          external={true}
        >Open activity</.a>
      </div>
      <.input
        id="form-try-activity"
        name="activity"
        type="select"
        value={@activity && @activity.id}
        options={Enum.map(@activities, &{activity_label(&1, @owner), &1.id})}
      />
    </form>
    <p :if={@written and @activities == [] and !@previewing} id="form-try-none" class="measure">
      {no_activity(@owner)}
    </p>
    <p :if={!@written and @blank != []} id="form-blank-page" class="measure">
      {render_slot(@blank)}
    </p>
    <p :if={@previewing} id="form-try-printing" class="hint mb-3">
      <.spinner>Printing it…</.spinner>
    </p>
    <p :if={@preview_error} id="form-try-error" class="measure">{@preview_error}</p>
    <div :if={@pages != []} id="form-pages" class="flex flex-col gap-4">
      <img
        :for={{png, n} <- Enum.with_index(@pages, 1)}
        id={"form-page-#{n}"}
        src={"data:image/png;base64," <> Base.encode64(png)}
        alt={page_alt(n, length(@pages), @written)}
        class="w-full border border-border-subtle shadow-sm"
      />
    </div>
    """
  end

  defp page_alt(n, count, true), do: "Page #{n} of #{count}, marked SAMPLE"
  defp page_alt(n, count, false), do: "Page #{n} of #{count} of the agency's blank form"

  @doc "An activity in the picker: Coast Range SAR's in its own zone, a team's in the team's."
  def activity_label(activity, owner),
    do: "#{activity.title}, #{Service.Format.date_short(activity.started_at, zone(owner))}"

  defp zone(%Organization{}), do: App.CoastRange.timezone()
  defp zone(team), do: team.timezone

  defp tried_on(%Organization{}), do: "Tried on Coast Range SAR"
  defp tried_on(_team), do: "Tried on"

  defp no_activity(%Organization{}), do: "Coast Range SAR has no activity this form shows on."
  defp no_activity(_team), do: "Your team has no activity this form shows on."
end
