defmodule Web.Components.MemberTabs do
  use Web, :function_component

  attr :member, :map, required: true

  attr :equipment, :list,
    default: [],
    doc: "the items the member holds, from load_sidebar/1; Equipment shows when there are any"

  attr :active_tab, :atom,
    required: true,
    values: [
      :attendance,
      :qualifications,
      :groups,
      :equipment,
      :standing,
      :card,
      :fields,
      :history
    ]

  attr :fields?, :boolean,
    default: false,
    doc: "whether the team copies member fields; Fields shows when it does"

  attr :team_admin?, :boolean,
    default: false,
    doc: "adds Equipment, Standing, ID card, Fields, and History"

  # Standing, ID card, Fields, and History are team admins' own records (#440, #681), and
  # the team's equipment pages are theirs too. A member sees what they hold, and their
  # own fields, on Your membership.
  def member_tabs(assigns) do
    ~H"""
    <.tabs label="Member">
      <:tab
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}"}
        current={@active_tab == :attendance}
      >
        Attendance
      </:tab>
      <:tab
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/qualifications"}
        current={@active_tab == :qualifications}
      >
        Qualifications
      </:tab>
      <:tab
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/groups"}
        current={@active_tab == :groups}
      >
        Groups
      </:tab>
      <:tab
        :if={@team_admin? and (@equipment != [] or @active_tab == :equipment)}
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/equipment"}
        current={@active_tab == :equipment}
      >
        Equipment
      </:tab>
      <:tab
        :if={@team_admin?}
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/standing"}
        current={@active_tab == :standing}
      >
        Standing
      </:tab>
      <:tab
        :if={@team_admin?}
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/card"}
        current={@active_tab == :card}
      >
        ID card
      </:tab>
      <:tab
        :if={@team_admin? and (@fields? or @active_tab == :fields)}
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/fields"}
        current={@active_tab == :fields}
      >
        Fields
      </:tab>
      <:tab
        :if={@team_admin?}
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/history"}
        current={@active_tab == :history}
      >
        History
      </:tab>
    </.tabs>
    """
  end
end
