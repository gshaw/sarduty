defmodule Web.ActivityFormsLive do
  @moduledoc """
  An activity's Forms tab (#1018): the activity's own page, team admins only, as an
  organization's forms are. Web.ActivityLive draws it; this module exists so the route
  keeps the team admin access members' tabs don't have.
  """
  use Web, :live_view_app_layout

  defdelegate mount(params, session, socket), to: Web.ActivityLive
  defdelegate handle_params(params, uri, socket), to: Web.ActivityLive
  defdelegate handle_info(message, socket), to: Web.ActivityLive
  defdelegate handle_event(event, params, socket), to: Web.ActivityLive
  defdelegate render(assigns), to: Web.ActivityLive
end
