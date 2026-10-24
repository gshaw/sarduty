defmodule Web.Components.MemberTabs do
  use Web, :function_component

  attr :member, :map, required: true

  attr :equipment, :list,
    default: [],
    doc: "the items the member holds, from load_sidebar/1; Equipment shows when there are any"

  attr :active_tab, :atom,
    required: true,
    values: [:attendance, :qualifications, :groups, :equipment, :standing, :card, :history]

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
        :if={@equipment != [] or @active_tab == :equipment}
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/equipment"}
        current={@active_tab == :equipment}
      >
        Equipment
      </:tab>
      <:tab
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/standing"}
        current={@active_tab == :standing}
      >
        Standing
      </:tab>
      <:tab
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/card"}
        current={@active_tab == :card}
      >
        ID card
      </:tab>
      <:tab
        navigate={~p"/teams/#{@member.team}/members/#{@member.id}/history"}
        current={@active_tab == :history}
      >
        History
      </:tab>
    </.tabs>
    """
  end
end
