defmodule Web.Components.MemberTabs do
  use Web, :function_component

  import Web.Components.A

  attr :member, :map, required: true
  attr :active_tab, :atom, required: true, values: [:attendance, :qualifications, :groups, :card]

  def member_tabs(assigns) do
    ~H"""
    <div>
      <nav class="tabs" aria-label="Tabs">
        <.tab
          navigate={~p"/teams/#{@member.team}/members/#{@member.id}"}
          current={@active_tab == :attendance}
        >
          Attendance
        </.tab>
        <.tab
          navigate={~p"/teams/#{@member.team}/members/#{@member.id}/qualifications"}
          current={@active_tab == :qualifications}
        >
          Qualifications
        </.tab>
        <.tab
          navigate={~p"/teams/#{@member.team}/members/#{@member.id}/groups"}
          current={@active_tab == :groups}
        >
          Groups
        </.tab>
        <.tab
          navigate={~p"/teams/#{@member.team}/members/#{@member.id}/card"}
          current={@active_tab == :card}
        >
          ID card
        </.tab>
      </nav>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :current, :boolean, required: true
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <.a kind={:custom} navigate={@navigate} aria-current={@current && "page"}>
      {render_slot(@inner_block)}
    </.a>
    """
  end
end
