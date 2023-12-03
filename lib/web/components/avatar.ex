defmodule Web.WebComponents.Avatar do
  use Web, :function_component

  import Web.CoreComponents

  attr :initials, :string, required: true

  def avatar(assigns) do
    ~H"""
    <div class="avatar placeholder">
      <div class="bg-primary text-primary-content rounded-full w-8">
        <span class="text-xs">
          <.icon name="hero-user" class="h-5 w-5" />
          <%!-- <%= @initials %> --%>
        </span>
      </div>
    </div>
    """
  end
end
