defmodule Web.ActivityTravelLive do
  @moduledoc """
  An activity's Travel tab (#230): the activity's own page, team admins only.
  Web.ActivityLive draws it, with Web.Components.TravelTab; this module exists so the
  route keeps the team admin access members' tabs don't have, as History's does.
  """
  use Web, :live_view_app_layout

  defdelegate mount(params, session, socket), to: Web.ActivityLive
  defdelegate handle_params(params, uri, socket), to: Web.ActivityLive
  defdelegate handle_info(message, socket), to: Web.ActivityLive
  defdelegate handle_event(event, params, socket), to: Web.ActivityLive
  defdelegate render(assigns), to: Web.ActivityLive
end
