defmodule Web.ActivityHistoryLive do
  @moduledoc """
  An activity's History tab: the activity's own page, team admins only, since the history
  can hold contact details and addresses. Web.ActivityLive draws it; this module exists
  so the route keeps the team admin access members' tabs don't have.
  """
  use Web, :live_view_app_layout

  defdelegate mount(params, session, socket), to: Web.ActivityLive
  defdelegate handle_params(params, uri, socket), to: Web.ActivityLive
  defdelegate handle_info(message, socket), to: Web.ActivityLive
  defdelegate handle_event(event, params, socket), to: Web.ActivityLive
  defdelegate render(assigns), to: Web.ActivityLive
end
