defmodule Web.StaticChanged do
  @moduledoc """
  Gets a page open since before a deploy onto the new JavaScript and CSS. A tab keeps the
  assets it loaded, so after a deploy it runs old code until someone reloads it.

  Every LiveView mounts this (see `Web.live_view/2`). When the tab's assets are out of date
  (`Phoenix.LiveView.static_changed?/1`):

    * going to another page loads it in full rather than live, so nothing typed is lost;
    * the open page, reconnecting after the deploy, shows a toast with a link to reload it,
      since a reload there would lose what someone typed.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and static_changed?(socket) do
      navigation? = navigation?(get_connect_params(socket))

      {:cont,
       attach_hook(socket, :static_changed, :handle_params, fn _params, url, socket ->
         reload(navigation?, url, socket)
       end)}
    else
      {:cont, assign(socket, :static_changed_url, nil)}
    end
  end

  @doc """
  Whether a mount is going to another page, from its connect params. That sends a referer
  and mounts for the first time. A page that just loaded sends no referer, so it never
  reloads and can't loop. A page that reconnects has mounted before, and sends its referer
  again.
  """
  def navigation?(params), do: is_binary(params["_live_referer"]) and params["_mounts"] == 0

  defp reload(true, url, socket), do: {:halt, redirect(socket, external: url)}
  defp reload(false, url, socket), do: {:cont, assign(socket, :static_changed_url, url)}
end
