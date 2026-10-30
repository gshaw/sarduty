defmodule Web.Components.Columns do
  @moduledoc """
  The standard columns (#740): one cell for each column that recurs across tables, so it
  reads the same on every page. Put each in a `<:col>` labelled with the column's name.

  A record column is a record's name linked to its page, with the badge for its state:
  Member, Activity, Item, Qualification, and Group. A value column is one formatter and
  one alignment: Date, Expires, Hours (right), and Last attended.
  Web.StandardColumnsTest fails on one built by hand. /styles/table shows them all.
  """
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H, only: [activity_title: 1, activity_kind_mark: 1]
  import Web.Components.Standing, only: [standing_badge: 1]

  alias App.Model.Activity
  alias App.Operation.BuildGroupRulePreview
  alias Service.Format

  attr :member, :map, required: true, doc: "with `id` and `name`"
  attr :team, :any, required: true

  attr :standing, :any,
    default: :active,
    doc:
      "from Standing.visible_by_member/4 on a page members can open, else by_member/3; nil is active"

  attr :path, :string, default: nil, doc: "the link, such as a tab; the member page by default"

  attr :label_for, :string,
    default: nil,
    doc: "the row's checkbox: the name labels it rather than links"

  attr :link, :boolean, default: true, doc: "false for the name alone, such as on a scanner"
  attr :id, :string, default: nil, doc: "the badge's id"

  @doc "Member: the name, linked to the member's page, and the standing badge."
  def member_cell(assigns) do
    ~H"""
    <span class="whitespace-nowrap">
      <label :if={@label_for} for={@label_for}>{@member.name}</label>
      <span :if={!@label_for and !@link}>{@member.name}</span>
      <.a :if={!@label_for and @link} navigate={@path || ~p"/teams/#{@team}/members/#{@member.id}"}>{@member.name}</.a>
    </span>
    <.standing_badge id={@id} standing={@standing || :active} />
    """
  end

  attr :activity, :map, required: true, doc: "with `id`, `ref_id`, `title`, and its kind"
  attr :team, :any, required: true
  attr :path, :string, default: nil, doc: "the link, such as a tab; the activity page by default"
  attr :kind, :boolean, default: true, doc: "false when the table has a Kind column"
  attr :now, :any, default: nil, doc: "the time now, when the page has one"

  @doc ~s(Activity: "ref: title", linked to the activity, Draft once it has finished unpublished, and its kind.)
  def activity_cell(assigns) do
    ~H"""
    <.a navigate={@path || ~p"/teams/#{@team}/activities/#{@activity.id}"}><.activity_title activity={
      @activity
    } /></.a>
    <.badge :if={Activity.finished_draft?(@activity, @now || DateTime.utc_now())}>Draft</.badge>
    <.activity_kind_mark :if={@kind} activity={@activity} class="ml-2 whitespace-nowrap" />
    """
  end

  attr :item, :map, required: true, doc: "an EquipmentItem"
  attr :team, :any, default: nil, doc: "for the link"
  attr :link, :boolean, default: true, doc: "false for a member: item pages are for team admins"

  @doc "Item: the title, linked to the item, and its status unless it's operational."
  def item_cell(assigns) do
    ~H"""
    <.a :if={@link} navigate={~p"/teams/#{@team}/equipment/#{@item.id}"}>{@item.title}</.a>
    <span :if={!@link}>{@item.title}</span>
    <.item_status item={@item} />
    """
  end

  attr :item, :map, required: true

  # Red for unserviceable or lost, grey for the rest; nothing when operational.
  defp item_status(%{item: %{status: "operational"}} = assigns), do: ~H""

  defp item_status(%{item: %{status: status}} = assigns)
       when status in ["unserviceable", "lost"] do
    ~H"""
    <.badge kind={:danger}>{String.capitalize(@item.status)}</.badge>
    """
  end

  defp item_status(assigns) do
    ~H"""
    <.badge>{String.capitalize(@item.status)}</.badge>
    """
  end

  attr :qualification, :map, required: true, doc: "with `id` and `title`"
  attr :team, :any, required: true

  attr :link, :boolean,
    default: true,
    doc: "false for a member: qualification pages are for team admins"

  @doc "Qualification: the title, linked to the qualification."
  def qualification_cell(assigns) do
    ~H"""
    <.a :if={@link} navigate={~p"/teams/#{@team}/qualifications/#{@qualification.id}"}>{@qualification.title}</.a>
    <span :if={!@link}>{@qualification.title}</span>
    """
  end

  attr :group, :map, required: true, doc: "with `id` and `title`"
  attr :team, :any, default: nil, doc: "for the link"
  attr :link, :boolean, default: true, doc: "false for a member: group pages are for team admins"

  @doc "Group: the title, linked to the group."
  def group_cell(assigns) do
    ~H"""
    <.a :if={@link} navigate={~p"/teams/#{@team}/groups/#{@group.id}"}>{@group.title}</.a>
    <span :if={!@link}>{@group.title}</span>
    """
  end

  attr :value, :any, default: nil, doc: "a DateTime, shown in `timezone`, or a Date"

  attr :activity, :map,
    default: nil,
    doc: "an activity in place of `value`: its start, or its month for a chore activity"

  attr :timezone, :string, required: true

  attr :times, :boolean,
    default: false,
    doc: "with `activity`, its start and end under the date: the Activities list only"

  @doc """
  Date: "Mar 1, 2026" in the team's zone. Given an activity, "Oct 2026" for a chore
  activity, which stands for its month. Left, `w-px whitespace-nowrap`.
  """
  def date_cell(%{activity: %{} = activity} = assigns) do
    %{started_at: started_at, finished_at: finished_at} = activity

    assigns =
      assign(assigns,
        chores?: Activity.shown_kind(activity) == "chores",
        days_later: Service.Convert.days_later(started_at, finished_at, assigns.timezone)
      )

    ~H"""
    <%= if @chores? do %>
      {Format.month_year(@activity.started_at, @timezone)}
    <% else %>
      {date(@activity.started_at, @timezone)}
      <div :if={@times} class="hint">
        {Format.time_range(@activity.started_at, @activity.finished_at, @timezone)}<sup
          :if={@days_later > 0}
          aria-hidden="true"
        >+{@days_later}</sup><span :if={@days_later > 0} class="sr-only">, ending {Format.days(
          @days_later
        )} later</span>
      </div>
    <% end %>
    """
  end

  def date_cell(assigns) do
    ~H"""
    {date(@value, @timezone)}
    """
  end

  defp date(nil, _timezone), do: nil
  defp date(%Date{} = date, _timezone), do: Format.date_short(date)
  defp date(datetime, timezone), do: Format.date_short(datetime, timezone)

  attr :value, :any, required: true, doc: "when it ends, a DateTime or nil for never"
  attr :now, :any, default: nil, doc: "the time now, when the page has one"
  attr :timezone, :string, required: true

  @doc """
  Expires: the date, "Expired" before it once past, and the days left within
  #{BuildGroupRulePreview.expiring_days()} days, the window group rules warn in. Left,
  `w-px whitespace-nowrap`.
  """
  def expires_cell(assigns) do
    now = assigns.now || DateTime.utc_now()
    assigns = assign(assigns, :expiry, BuildGroupRulePreview.expiry(assigns.value, now))

    ~H"""
    <span :if={@expiry == :expired}>Expired</span>
    {date(@value, @timezone)}
    <.badge :if={is_integer(@expiry)} kind={:warning}>{Format.days(@expiry)}</.badge>
    """
  end

  attr :minutes, :any, required: true, doc: "nil for a blank cell"

  @doc ~s(Hours: "2h 30m", from Format.duration/1. Right-aligned, `w-px whitespace-nowrap`.)
  def hours_cell(assigns) do
    ~H"""
    {@minutes && Format.duration(@minutes)}
    """
  end

  attr :value, :any, required: true, doc: "when they last attended, or nil"
  attr :now, :any, default: nil, doc: "the time now, when the page has one"
  attr :timezone, :string, required: true
  attr :id, :string, default: nil

  @doc ~s(Last attended: "12 days ago", or "Never", with the date on hover. Left, `w-px whitespace-nowrap`.)
  def last_attended_cell(assigns) do
    ~H"""
    <span id={@id} title={date(@value, @timezone)}>
      {Format.days_ago(@value, @now || DateTime.utc_now(), @timezone) || "Never"}
    </span>
    """
  end
end
