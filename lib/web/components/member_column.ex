defmodule Web.Components.MemberColumn do
  @moduledoc """
  The Member column (#740), for every table that lists the members of something: the
  name linked to the member page, and the standing badge. Put it in a `<:col
  label="Member">`. Web.MemberColumnTest fails on a table that links to a member by hand.
  """
  use Web, :function_component

  import Web.Components.A
  import Web.Components.Standing, only: [standing_badge: 1]

  attr :member, :map, required: true, doc: "with `id` and `name`"
  attr :team, :any, required: true

  attr :standing, :any,
    default: :active,
    doc: "from Standing.visible_by_member/4; nil for a member with none is active"

  attr :path, :string, default: nil, doc: "the link, such as a tab; the member page by default"

  attr :label_for, :string,
    default: nil,
    doc: "the row's checkbox: the name labels it rather than links"

  attr :link, :boolean, default: true, doc: "false for the name alone, such as on a scanner"
  attr :id, :string, default: nil, doc: "the badge's id"

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
end
