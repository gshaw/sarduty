defmodule Web.Components.MemberTabs do
  use Web, :function_component

  import Web.Components.A

  attr :member, :map, required: true
  attr :active_tab, :atom, required: true, values: [:attendance, :qualifications, :groups]

  def member_tabs(assigns) do
    ~H"""
    <div class="border-b border-hr mb-6">
      <nav class="flex gap-2" aria-label="Tabs">
        <.tab
          navigate={~p"/#{@member.team.subdomain}/members/#{@member.id}"}
          current={@active_tab == :attendance}
        >
          Attendance
        </.tab>
        <.tab
          navigate={~p"/#{@member.team.subdomain}/members/#{@member.id}/qualifications"}
          current={@active_tab == :qualifications}
        >
          Qualifications
        </.tab>
        <.tab
          navigate={~p"/#{@member.team.subdomain}/members/#{@member.id}/groups"}
          current={@active_tab == :groups}
        >
          Groups
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
    <.a
      kind={:custom}
      navigate={@navigate}
      aria-current={@current && "page"}
      class={[
        "py-3 px-4 font-medium text-sm border-b-2 transition-colors duration-200",
        @current && "border-primary-1 text-primary-1 bg-primary-1/10",
        !@current && "border-transparent text-secondary-1 hover:text-base-content hover:bg-base-2"
      ]}
    >
      {render_slot(@inner_block)}
    </.a>
    """
  end
end
