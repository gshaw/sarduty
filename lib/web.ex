defmodule Web do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use Web, :controller
      use Web, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: Web.Layouts]

      import Plug.Conn
      import Web.Gettext

      unquote(verified_routes())
    end
  end

  def function_component do
    quote do
      use Phoenix.Component

      unquote(html_helpers())
    end
  end

  def live_view_marketing do
    quote do
      use Phoenix.LiveView, layout: {Web.Layouts, :marketing}

      import Web.WebComponents.A

      unquote(html_helpers())
    end
  end

  def live_view_app do
    quote do
      use Phoenix.LiveView, layout: {Web.Layouts, :app}

      import Web.WebComponents.A
      import Web.WebComponents.AttendanceTable
      import Web.WebComponents.D4HComponents
      import Web.WebComponents.Pagination

      unquote(html_helpers())
    end
  end

  def live_view_narrow do
    quote do
      use Phoenix.LiveView, layout: {Web.Layouts, :narrow}

      import Web.WebComponents.A

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      import Web.WebComponents.A
      import Web.WebComponents.Avatar
      import Web.WebComponents.NavBar

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import Web.CoreComponents
      import Web.Gettext

      alias Phoenix.LiveView.AsyncResult
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: Web.Endpoint,
        router: Web.Router,
        statics: Web.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
