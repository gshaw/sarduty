defmodule Web.Components.PersonHead do
  @moduledoc """
  A member's name at the top of their page: a round photo, or their initials when D4H has
  none, their standing when they aren't active, and one line of facts. The team member
  page and Your membership both open with it. See /styles/person-head.
  """
  use Web, :function_component

  import Web.Components.Standing, only: [standing_badge: 1]

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :name, :string, required: true
  attr :photo, :string, required: true, doc: "the photo's path; a 404 leaves the initials"
  attr :standing, :any, default: :active, doc: "from MemberAwayPeriod.standing_today/3"
  attr :item_count, :integer, default: 0, doc: "the items the member holds, for Retired"
  attr :facts, :list, default: [], doc: "short strings for the line under the name"
  slot :actions, doc: "buttons on the right"

  def person_head(assigns) do
    ~H"""
    <div id={@id} class={["person-head", @class]}>
      <%!-- Ignored on update, so the photo a failed load removed stays gone. --%>
      <span id={"#{@id}-avatar"} class="avatar avatar-lg" phx-update="ignore">
        {Web.Navigation.initials(@name)}
        <img id={"#{@id}-photo"} src={@photo} alt="" onerror="this.remove()" />
      </span>
      <div class="min-w-0">
        <div class="person-head-title">
          <h1 class="title mb-0">{@name}</h1>
          <.standing_badge id={"#{@id}-standing"} standing={@standing} item_count={@item_count} />
        </div>
        <p :if={@facts != []} id={"#{@id}-facts"} class="hint mt-1 mb-0">
          {Enum.join(@facts, " · ")}
        </p>
      </div>
      <div :if={@actions != []} class="person-head-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc """
  The line under a member's name: their D4H role, when they joined, and when they last
  attended. A fact D4H doesn't have is left out.
  """
  def facts(member, last_attended_at, timezone) do
    [
      member.position,
      member.joined_at && "Joined #{Service.Format.month_year_long(member.joined_at, timezone)}",
      last_attended(last_attended_at, timezone)
    ]
    |> Enum.filter(&(&1 not in [nil, ""]))
  end

  defp last_attended(nil, _timezone), do: "Not attended yet"

  defp last_attended(started_at, timezone),
    do: "Last attended #{Service.Format.date_short(started_at, timezone)}"
end
