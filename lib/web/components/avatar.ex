defmodule Web.WebComponents.Avatar do
  use Web, :function_component

  import Web.CoreComponents

  attr :initials, :string, required: true

  def avatar(assigns) do
    ~H"""
    <span class="inline-flex items-center justify-center rounded-full bg-primary-1 h-8 w-8">
      <span class="leading-none font-medium text-primary-content text-sm">
        <.icon name="hero-user" class="h-5 w-5" />
        <%!-- <%= @initials %> --%>
      </span>
    </span>
    """
  end
end
