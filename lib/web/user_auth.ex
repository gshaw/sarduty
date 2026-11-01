defmodule Web.UserAuth do
  use Web, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias App.Accounts
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Organization
  alias App.Model.OrganizationAdmin
  alias App.Model.Team
  alias App.Operation.RecordUserSeen

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_sarduty_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  # Users who have logged in with this browser, kept after logging out, so wrong codes
  # someone else enters can't lock them out of it (#176). Signed, so it can't be made up.
  @known_browser_cookie "_sarduty_known_browser"
  @known_browser_options [sign: true, max_age: 60 * 60 * 24 * 365, same_site: "Lax"]
  @known_browser_users 5

  # The member a team admin views the team as (#425), by local id. Read through the URL's
  # team, so it only ever applies on that team.
  @view_as_key "view_as_member_id"

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  # Only the session cookie is set by default, and it ends when the browser closes.
  # `remember: true`, from the "Remember me" box, adds the 60-day remember-me cookie.
  def log_in_user(conn, user, opts \\ []) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_remember(token, Keyword.get(opts, :remember, false))
    |> remember_browser(user)
    |> redirect(to: user_return_to || signed_in_path(user))
  end

  defp maybe_remember(conn, token, true),
    do: put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)

  defp maybe_remember(conn, _token, false), do: conn

  defp remember_browser(conn, user) do
    ids = conn |> known_user_ids() |> List.delete(user.id)
    ids = Enum.take([user.id | ids], @known_browser_users)
    put_resp_cookie(conn, @known_browser_cookie, ids, @known_browser_options)
  end

  @doc "Whether this user has logged in with this browser before."
  def known_browser?(_conn, nil), do: false
  def known_browser?(conn, user), do: user.id in known_user_ids(conn)

  defp known_user_ids(conn) do
    conn = fetch_cookies(conn, signed: [@known_browser_cookie])

    case conn.cookies[@known_browser_cookie] do
      ids when is_list(ids) -> ids
      _none -> []
    end
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      Web.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def assign_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)

    conn
    |> assign(:current_user, user)
    |> assign(:current_team, default_team(user))
  end

  @doc """
  The team a page outside `/teams/:subdomain` treats as current, for the nav and where
  logging in lands: the team the user last opened when they still manage it, else their
  first by name, or nil.
  """
  def default_team(user), do: user |> managed_teams() |> pick_default_team(user)

  @doc """
  The top bar's menus on a page that isn't a LiveView, as a LiveView mounts them: every team
  the user manages, the members they log in as, and the organizations they are an admin
  of. The style guide uses it.
  """
  def assign_menus(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:managed_teams, managed_teams(user))
    |> assign(:member_logins, member_logins(user))
    |> assign(:user_organizations, user_organizations(user))
  end

  defp managed_teams(nil), do: []
  defp managed_teams(user), do: Team.get_managed_by(user.email, DateTime.utc_now())

  # The members this user logs in as, one per team with member logins on (#156).
  defp member_logins(nil), do: []
  defp member_logins(user), do: Member.get_logins(user.email, DateTime.utc_now())

  defp find_login(logins, subdomain), do: Enum.find(logins, &(&1.team.subdomain == subdomain))

  defp pick_default_team(_teams, nil), do: nil

  defp pick_default_team(teams, user) do
    Enum.find(teams, &(&1.id == user.last_team_id)) || List.first(teams)
  end

  # The team a URL's subdomain names, when this user may open it: an admin may open any.
  defp authorized_team(user, subdomain) do
    if user.is_admin do
      Team.get_by(subdomain: subdomain)
    else
      user.email
      |> Team.get_managed_by(DateTime.utc_now())
      |> Enum.find(&(&1.subdomain == subdomain))
    end
  end

  # The organization a URL's slug names, when this user may open it: one they are an
  # organization admin of, or any for a SAR Duty admin.
  defp authorized_organization(user, organizations, slug) do
    Enum.find(organizations, &(&1.slug == slug)) ||
      if(user.is_admin && is_binary(slug), do: Organization.get_by_slug(slug))
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule Web.PageLive do
        use Web, :live_view

        on_mount {Web.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{Web.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  # The page's path, kept current on live navigation, so the top bar can mark the section
  # it's in.
  def on_mount(:mount_current_path, _params, _session, socket) do
    socket =
      socket
      |> Phoenix.Component.assign(:current_path, nil)
      |> Phoenix.LiveView.attach_hook(:current_path, :handle_params, fn _params, uri, socket ->
        {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
      end)

    {:cont, socket}
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Log in to see this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  # Every page under /orgs/:slug (#512): `current_organization` for its organization
  # admins and SAR Duty admins; a 404 for anyone else, so the page doesn't say whether
  # the organization exists. An organization admin's visit stamps their Last seen.
  def on_mount(:ensure_org_access, params, _session, socket) do
    user = socket.assigns.current_user

    organization =
      authorized_organization(user, socket.assigns.user_organizations, params["slug"])

    if is_nil(organization), do: raise(Web.Status.NotFound)

    unless user.is_admin, do: OrganizationAdmin.record_seen(organization.id, user)

    {:cont, Phoenix.Component.assign(socket, current_organization: organization)}
  end

  # Every page under /admin: a 404 for anyone who isn't a SAR Duty admin, as on team and
  # organization pages, so the page doesn't say it exists (#513).
  def on_mount(:ensure_admin, _params, _session, socket) do
    if socket.assigns.current_user.is_admin,
      do: {:cont, socket},
      else: raise(Web.Status.NotFound)
  end

  # Every page under /teams/:subdomain (#406). The URL's team is `current_team` for
  # everyone. `team_admin?` when the user manages it in D4H or is a SAR Duty admin;
  # `current_member` when they log in as one of its members, else nil. The page's
  # `access` (see Web) decides who may open it: team admins only unless it says :team or
  # :member. Anyone else gets a 404, so the page doesn't say whether the team exists.
  def on_mount(:ensure_team_access, params, session, socket) do
    user = socket.assigns.current_user
    # mount_current_user loaded the user's member logins for the menu; reuse them.
    logins = socket.assigns[:member_logins] || member_logins(user)
    view_as = session[@view_as_key]
    page_access = page_access(socket.view)
    access = team_access!(user, logins, params["subdomain"], page_access, view_as)

    if access.team_admin?, do: RecordUserSeen.call(user, access.current_team.id)

    # `service` names where the team's records are, for text that sends the reader there.
    service = D4H.service_name(access.current_team)

    socket =
      socket
      |> Phoenix.Component.assign(Map.put(access, :service, service))
      |> guard_events(page_access, access)

    {:cont, socket}
  end

  # Who sends which events (#440). A team admin sends every event on the pages they open,
  # and a member every event on their own pages. Otherwise only some reach the page's
  # handle_event (see Web): a member on a team page sends its `view_events` and
  # `member_events`, and their other events stop silently since no control offers them.
  # A team admin viewing as a member sends only `view_events`, and is told nothing is
  # saved. Events a component handles (phx-target) go to the component, which checks for
  # itself.
  defp guard_events(socket, page_access, access),
    do: guard_events(socket, refusal(page_access, access))

  defp guard_events(socket, :none), do: socket

  defp guard_events(socket, refusal) do
    allowed =
      if refusal == :silent,
        do: view_events(socket.view) ++ member_events(socket.view),
        else: view_events(socket.view)

    Phoenix.LiveView.attach_hook(socket, :view_events, :handle_event, fn event, _params, s ->
      if event in allowed, do: {:cont, s}, else: {:halt, refuse(s, refusal)}
    end)
  end

  defp refuse(socket, :silent), do: socket
  defp refuse(socket, text), do: Phoenix.LiveView.put_flash(socket, :error, text)

  # Team admin pages stay the team admin's, even while viewing as a member.
  defp refusal(:admin, _access), do: :none
  defp refusal(_page_access, %{viewing_as: %Member{} = member}), do: view_as_refusal(member)
  defp refusal(:team, %{team_admin?: false}), do: :silent
  defp refusal(_page_access, _access), do: :none

  @doc """
  The events on `view` that only change what it shows, which everyone who opens it sends.
  """
  def view_events(view) do
    if function_exported?(view, :__view_events__, 0), do: view.__view_events__(), else: []
  end

  @doc "The actions on a team page `view` that members take too, but view as does not."
  def member_events(view) do
    if function_exported?(view, :__member_events__, 0), do: view.__member_events__(), else: []
  end

  # Who the user is on the URL's team, as `current_team`, `current_member`, and
  # `team_admin?`, when `access` lets them in; otherwise a 404. The LiveView hook and the
  # plug both decide here, so they never let in different people.
  #
  # A team admin viewing as a member (#425) is that member, and not a team admin, on every
  # page members open, so they see what the member sees. Team admin pages stay theirs.
  # `viewing_as` is the member, on every page, for the banner and the read-only checks.
  defp team_access!(user, logins, subdomain, access, view_as_id) do
    admin_team = authorized_team(user, subdomain)
    viewing_as = viewing_as(admin_team, view_as_id)

    {admin_team, member} =
      if viewing_as && access != :admin,
        do: {nil, viewing_as},
        else: {admin_team, find_login(logins, subdomain)}

    unless allowed?(access, admin_team, member), do: raise(Web.Status.NotFound)

    report_context(user, member, viewing_as)

    %{
      current_team: admin_team || member.team,
      current_member: member,
      team_admin?: admin_team != nil,
      viewing_as: viewing_as
    }
  end

  # So an error report on a member's page names whose page broke; view as them to see it.
  # Logger metadata, so it reaches crashes in this process, LiveView or request alike.
  defp report_context(user, member, viewing_as) do
    Honeybadger.context(
      user_id: user.id,
      member_id: member && member.id,
      viewing_as: viewing_as != nil
    )
  end

  defp viewing_as(nil, _id), do: nil
  defp viewing_as(_team, nil), do: nil

  defp viewing_as(team, id) do
    case Member.find(team, id) do
      nil -> nil
      member -> %{member | team: team}
    end
  end

  @doc "Starts viewing the team as `member` (#425): the member pages show what they see."
  def put_view_as(conn, member), do: put_session(conn, @view_as_key, member.id)

  @doc "Whether a team admin is viewing a team as a member (#425), for pages outside a team."
  def viewing_as?(session), do: session[@view_as_key] != nil

  @doc "What a page says when a team admin viewing as `member` tries to change something."
  def view_as_refusal(member), do: "You're viewing as #{member.name}, so nothing is saved."

  @doc "Stops viewing as a member, and returns the member's id, or nil."
  def delete_view_as(conn) do
    {get_session(conn, @view_as_key), delete_session(conn, @view_as_key)}
  end

  @doc "Who may open a team LiveView: `:admin` (the default), `:team`, or `:member`."
  def page_access(nil), do: :admin

  def page_access(view) do
    if Code.ensure_loaded?(view) and function_exported?(view, :__team_access__, 0),
      do: view.__team_access__(),
      else: :admin
  end

  @doc """
  Whether someone opens a page with `access`, as a team admin or as a member who logs in.
  The same rule as the team pages' hook; global search (#473) uses it to show only results
  that open.
  """
  def opens?(access, team_admin?, member?),
    do: allowed?(access, if(team_admin?, do: :team), if(member?, do: :member))

  defp allowed?(:admin, admin_team, _member), do: admin_team != nil
  defp allowed?(:team, admin_team, member), do: admin_team != nil or member != nil
  defp allowed?(:member, _admin_team, member), do: member != nil

  defp mount_current_user(socket, session) do
    socket
    |> Phoenix.Component.assign_new(:current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
    |> mount_current_team()
  end

  # The team for pages outside /teams/:subdomain, and every team the user manages, for the
  # account menu. One query for both. The member logins and the organizations they are an
  # admin of (#512) are for the menu too.
  defp mount_current_team(socket) do
    current_user = socket.assigns.current_user
    teams = managed_teams(current_user)

    socket
    |> Phoenix.Component.assign(current_team: pick_default_team(teams, current_user))
    |> Phoenix.Component.assign(managed_teams: teams)
    |> Phoenix.Component.assign(member_logins: member_logins(current_user))
    |> Phoenix.Component.assign(user_organizations: user_organizations(current_user))
  end

  defp user_organizations(nil), do: []
  defp user_organizations(user), do: OrganizationAdmin.organizations_for_email(user.email)

  @doc "Sends a logged-in user to their team rather than the login form."
  def redirect_if_user_is_authenticated(conn, _opts) do
    if user = conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(user))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_login_flash()
      |> maybe_store_return_to()
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc "A controller under /admin: a 404 for anyone who isn't a SAR Duty admin, like :ensure_admin."
  def require_admin(conn, _opts) do
    if conn.assigns.current_user.is_admin, do: conn, else: raise(Web.Status.NotFound)
  end

  # On the way to Take attendance the login page says what logging in is for (#475), so a
  # toast there would only cover it on the hall's iPad.
  defp put_login_flash(conn) do
    if conn.method == "GET" and conn |> current_path() |> Web.TakeAttendanceLive.path?(),
      do: conn,
      else: put_flash(conn, :error, "Log in to see this page.")
  end

  def require_authorized_team_subdomain(conn, _opts) do
    current_user = conn.assigns.current_user

    case authorized_team(current_user, conn.path_params["subdomain"]) do
      nil ->
        raise Web.Status.NotFound

      team ->
        RecordUserSeen.call(current_user, team.id)
        assign(conn, :current_team, team)
    end
  end

  @doc """
  The plug for a team route that members reach too (#406), like `access: :team`: assigns
  `current_team`, `current_member`, and `team_admin?`, or a 404 for anyone who is neither.
  """
  def require_team_access(conn, _opts) do
    user = conn.assigns.current_user
    subdomain = conn.path_params["subdomain"]
    access = team_access!(user, member_logins(user), subdomain, :team, view_as_id(conn))
    assign(conn, Map.to_list(access))
  end

  @doc """
  The plug for a member's own downloads: `member` is the logged-in member on the URL's
  team, or the member a team admin views as, with `viewing_as` set.
  """
  def require_team_member(conn, _opts) do
    user = conn.assigns.current_user
    subdomain = conn.path_params["subdomain"]
    access = team_access!(user, member_logins(user), subdomain, :member, view_as_id(conn))
    assign(conn, member: access.current_member, viewing_as: access.viewing_as)
  end

  defp view_as_id(conn), do: get_session(conn, @view_as_key)

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc """
  Where logging in lands: the team the user last opened when they still manage it, else
  their only or first team. Someone who manages none lands on their team's Dashboard as a
  member (#406), then their first organization (#512), an admin on /admin, and anyone
  else on the home page, which says why they have no team.
  """
  def signed_in_path(user) do
    team = default_team(user)

    cond do
      team -> ~p"/teams/#{team}"
      member = user |> member_logins() |> List.first() -> ~p"/teams/#{member.team}"
      organization = user |> user_organizations() |> List.first() -> ~p"/orgs/#{organization}"
      user.is_admin -> ~p"/admin"
      true -> ~p"/"
    end
  end
end
