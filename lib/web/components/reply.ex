defmodule Web.Components.Reply do
  @moduledoc """
  A member's reply to an activity they're invited to (#444): I'll be there and Can't
  make it, then their reply and Change, which brings the buttons back. Signed up adds
  Add to calendar. Replies close at the start. `Web.Components.ReplyControl` sends them; this is what it shows, and the
  counts above it. See /styles/reply.
  """
  use Web, :function_component

  alias App.Model.Activity
  alias App.Model.Member

  @doc """
  Who replies for the person on the page: the member they log in as, or a team admin's
  own member row. A team admin viewing as a member is that member. Nil for anyone else.
  """
  def replier(%{current_member: %Member{} = member}, _now), do: member

  def replier(%{team_admin?: true, current_user: user, current_team: team}, now),
    do: Member.find_by_email(team, user.email, now)

  def replier(_assigns, _now), do: nil

  @doc "Whether the member can reply now: invited, and before the start."
  def open?(nil, _activity, _now), do: false

  def open?(_invitation, activity, now),
    do: Activity.open?(activity, now)

  @doc """
  The member's reply as the control shows it: `:ask` for the buttons, else `:yes` or
  `:no`. Change asks again.
  """
  def state(_invitation, true = _changing?), do: :ask
  def state(%{status: "attending"}, _changing?), do: :yes
  def state(%{status: "absent"}, _changing?), do: :no
  def state(_invitation, _changing?), do: :ask

  @doc """
  The activity's counts, as people read them: "6 signed up · 2 can't make it · 5 no
  reply", and from the start "6 attended · 2 absent · 5 no reply". A zero is left out,
  except the first.
  """
  def counts_text(%{attending: yes, absent: no, requested: none}, started?) do
    {yes_words, no_words} =
      if started?, do: {"attended", "absent"}, else: {"signed up", "can't make it"}

    [{yes, yes_words}, {no, no_words}, {none, "no reply"}]
    |> Enum.with_index()
    |> Enum.reject(fn {{n, _words}, index} -> n == 0 and index > 0 end)
    |> Enum.map_join(" · ", fn {{n, words}, _index} ->
      Service.Format.count(n, one: "%d #{words}", many: "%d #{words}")
    end)
  end

  @doc """
  A D4H status in the reply words, or in D4H's once the activity starts: "Signed up",
  then "Attended".
  """
  def status_text("attending", false = _started?), do: "Signed up"
  def status_text("attending", true), do: "Attended"
  def status_text("absent", false), do: "Can't make it"
  def status_text("absent", true), do: "Absent"
  def status_text("requested", _started?), do: "No reply"

  @doc ~s(A status's marker, the square before its words: "signed-up" for `.marker-signed-up`.)
  def marker("attending"), do: "signed-up"
  def marker("absent"), do: "cant-make-it"
  def marker("requested"), do: "no-reply"

  @doc """
  The signed up or attended count alone, for a line that has no room for the rest:
  "6 signed up", "6 attended".
  """
  def yes_text(%{attending: yes}, started?) do
    words = if started?, do: "attended", else: "signed up"
    Service.Format.count(yes, one: "%d #{words}", many: "%d #{words}")
  end

  attr :id, :string, required: true
  attr :state, :atom, required: true, values: [:ask, :yes, :no]
  attr :size, :atom, default: :md, values: [:md, :sm]
  attr :target, :any, default: nil, doc: "the control that takes the clicks"

  attr :change_href, :string,
    default: nil,
    doc: "makes Change a link, for a page that replies with a form (#488)"

  attr :calendar_href, :string,
    default: nil,
    doc: "the activity's .ics, for Add to calendar once signed up"

  @doc "The two buttons, or the member's reply and Change."
  def reply(assigns) do
    ~H"""
    <div id={@id} class={["reply", @size == :sm && "reply-sm"]}>
      <div :if={@state == :ask} class="reply-buttons">
        <.button
          id={"#{@id}-yes"}
          variant={:success}
          size={@size}
          phx-click="reply"
          phx-disable-with="Sending…"
          phx-value-reply="yes"
          phx-target={@target}
        >
          I'll be there
        </.button>
        <.button
          id={"#{@id}-no"}
          size={@size}
          phx-click="reply"
          phx-disable-with="Sending…"
          phx-value-reply="no"
          phx-target={@target}
        >
          Can't make it
        </.button>
      </div>
      <p :if={@state != :ask} class="reply-row">
        <span :if={@state == :yes} id={"#{@id}-state"} class="reply-state is-yes">
          <.icon name="circle-check" size={@size} /> Signed up
        </span>
        <span :if={@state == :no} id={"#{@id}-state"} class="reply-state">Can't make it</span>
        <.button
          :if={!@change_href}
          id={"#{@id}-change"}
          variant={:link}
          size={@size}
          phx-click="change"
          phx-target={@target}
        >
          Change
        </.button>
        <.button
          :if={@change_href}
          id={"#{@id}-change"}
          variant={:link}
          size={@size}
          href={@change_href}
        >
          Change
        </.button>
        <.button
          :if={@state == :yes && @calendar_href}
          id={"#{@id}-calendar"}
          variant={:link}
          size={@size}
          href={@calendar_href}
        >
          <%!-- Black, as at the start of every action link. --%>
          <.icon name="calendar-plus" size={@size} class="text-text" /> Add to calendar
        </.button>
      </p>
    </div>
    """
  end
end
