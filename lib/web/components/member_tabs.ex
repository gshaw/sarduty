defmodule Web.Components.MemberTabs do
  use Web, :function_component

  import Web.Components.A

  attr :member, :map, required: true
  attr :active_tab, :atom, required: true, values: [:attendance, :qualifications]

  def member_tabs(assigns) do
    ~H"""
    <div class="border-b border-gray-200 mb-6">
      <nav class="flex gap-2" aria-label="Tabs">
        <.a
          navigate={~p"/#{@member.team.subdomain}/members/#{@member.id}"}
          class={[
            "py-3 px-4 font-medium text-sm border-b-2 transition-colors duration-200",
            (@active_tab == :attendance && "border-blue-500 text-blue-600 bg-blue-50") ||
              "border-transparent text-gray-500 hover:text-gray-700 hover:bg-gray-100"
          ]}
        >
          Attendance
        </.a>
        <.a
          navigate={~p"/#{@member.team.subdomain}/members/#{@member.id}/qualifications"}
          class={[
            "py-3 px-4 font-medium text-sm border-b-2 transition-colors duration-200",
            (@active_tab == :qualifications && "border-blue-500 text-blue-600 bg-blue-50") ||
              "border-transparent text-gray-500 hover:text-gray-700 hover:bg-gray-100"
          ]}
        >
          Qualifications
        </.a>
      </nav>
    </div>
    """
  end
end
