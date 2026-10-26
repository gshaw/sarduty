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
      use Gettext, backend: Web.Gettext

      unquote(verified_routes())
    end
  end

  def function_component do
    quote do
      use Phoenix.Component

      unquote(html_helpers())
    end
  end

  def live_view_marketing_layout(opts \\ []), do: live_view({Web.Layouts, :marketing}, opts)
  def live_view_app_layout(opts \\ []), do: live_view({Web.Layouts, :app}, opts)
  def live_view_verify_layout(opts \\ []), do: live_view({Web.Layouts, :verify}, opts)

  # One task done with a phone or iPad in hand: one centred column at every width, no side
  # navigation, and the compact top bar. `size: :tool`, 48rem, is for a tool with a list,
  # such as a scanner; the default, 28rem, for one short form. See /styles/layout.
  def live_view_narrow_layout(opts \\ []) do
    {size, opts} = Keyword.pop(opts, :size, :form)

    case size do
      :form -> live_view({Web.Layouts, :narrow}, opts)
      :tool -> live_view({Web.Layouts, :narrow_tool}, opts)
    end
  end

  # Every layout gets the same components, so a page can move to another layout
  # without changing its imports. Components only one or two pages use are imported
  # by those pages.
  #
  # `access` says who opens a page under /teams/:subdomain (#406): `:admin`, the default,
  # for team admins; `:team` for its members too; `:member` for members only, their own
  # pages. `use Web, {:live_view_app_layout, access: :team}`. Web.UserAuth checks it, so a
  # page nobody marked stays closed.
  #
  # `view_events` are the page's events that only change what it shows, such as a filter
  # form's "change" (#440). A member on an `access: :team` page, and a team admin viewing
  # as a member on any page members open, send only those: Web.UserAuth drops the rest,
  # so opening a page never opens its actions, and view as stays read only.
  # `use Web, {:live_view_app_layout, access: :team, view_events: ["change"]}`.
  #
  # `member_events` are the few actions a team page gives members too, such as a scan on
  # Take attendance (#475). Members send them; a team admin viewing as one does not.
  defp live_view(layout, opts) do
    access = Keyword.get(opts, :access, :admin)
    view_events = Keyword.get(opts, :view_events, [])
    member_events = Keyword.get(opts, :member_events, [])
    true = access in [:admin, :team, :member]
    true = member_events == [] or access == :team

    quote do
      use Phoenix.LiveView, layout: unquote(layout)

      on_mount Web.StaticChanged

      @doc false
      def __team_access__, do: unquote(access)

      @doc false
      def __view_events__, do: unquote(view_events)

      @doc false
      def __member_events__, do: unquote(member_events)

      import Web.Components.A
      import Web.Components.Breadcrumbs
      import Web.Components.D4H
      import Web.Components.HeadingRow
      import Web.Components.Markdown
      import Web.Components.Pagination
      import Web.Components.RowLink
      import Web.Components.Table

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

      import Web.Components.A
      import Web.Components.NavBar

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import Web.Components.Core
      import Web.Components.Messages
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

  defmacro __using__({which, opts}) when is_atom(which) and is_list(opts) do
    apply(__MODULE__, which, [opts])
  end
end
