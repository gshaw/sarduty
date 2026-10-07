defmodule Web.Router do
  use Web, :router
  use Honeybadger.Plug

  import Web.UserAuth

  # Honeybadger's default skips only 404s. Other 4xx are the client's doing: a JSON
  # Accept header on a page (406), a stale CSRF token (403), a malformed body (400).
  @impl Plug.ErrorHandler
  def handle_errors(conn, %{reason: reason} = error) do
    if Plug.Exception.status(reason) < 500, do: :ok, else: super(conn, error)
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :assign_current_user
  end

  # The verify site (verify.sarduty.com): a card's QR code opens /<code> here. No login,
  # and the app's session cookie never reaches it, since that cookie is host-only. First,
  # so `/` on this host is the check rather than the home page.
  pipeline :verify do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", Web, host: "verify." do
    pipe_through :verify

    live_session :verify, session: {Web.VerifyLimit, :session, []} do
      live "/", VerifyLive
      # An organization's own start page, until it has its own verify host. Codes look
      # like K7Q4-M2XA, so "orgs" can't be one.
      live "/orgs/:slug", VerifyLive
      # Tax credit letters (#207). "letters" has an L, which card codes never do.
      live "/letters", VerifyLetterLive
      live "/letters/:ref", VerifyLetterLive
      live "/:code", VerifyLive
    end

    # Card images live here, on the public host with no session cookie. Google Wallet
    # objects hold the banner's URL.
    get "/:code/photo", MemberCardController, :photo
    get "/:code/banner", MemberCardController, :banner
    get "/*path", VerifyController, :to_app
  end

  # Apple Wallet calls these with JSON bodies and its own auth header: no session, no
  # CSRF token, and an Accept header of its own choosing.
  scope "/wallet/v1", Web do
    post "/devices/:device/registrations/:pass_type/:serial", WalletController, :register
    delete "/devices/:device/registrations/:pass_type/:serial", WalletController, :unregister
    get "/devices/:device/registrations/:pass_type", WalletController, :serial_numbers
    get "/passes/:pass_type/:serial", WalletController, :pass
    post "/log", WalletController, :log
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sarduty, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Web.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # URL rules are in docs/urls.md. Each top-level path here is listed in
  # test/web/router_test.exs, so a new one is added on purpose. Nothing fixed goes
  # directly under /teams/ or /orgs/: it would block a team or organization with that
  # name. That's why sign-up is /signup, not /teams/new.
  scope "/", Web do
    pipe_through :browser

    # The client IP rides in the session for sign-up's security events (Web.VerifyLimit).
    live_session :current_user_session,
      session: {Web.VerifyLimit, :session, []},
      on_mount: [{Web.UserAuth, :mount_current_path}, {Web.UserAuth, :mount_current_user}] do
      live "/", HomePageLive
      live "/signup", TeamSignupLive
      # Taking attendance at the door. The token is the only access: no login.
      live "/attendance/:token", AttendanceLinkLive
    end

    # Short links, such as an attendance link. Lowercase codes, unlike an ID card's.
    get "/s/:code", ShortLinkController, :show

    get "/styles", StyleGuideController, :index
    get "/styles/:page", StyleGuideController, :show

    # Public, before the team scope: Google Wallet objects fetch these.
    get "/teams/:subdomain/logo", TeamController, :logo
    get "/orgs/:slug/logo", OrganizationController, :logo

    post "/login/code", UserSessionController, :request_code
    post "/login", UserSessionController, :create
    delete "/logout", UserSessionController, :delete
  end

  # Asking for a login code and entering it. Someone already logged in goes to their team
  # instead.
  scope "/", Web do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :login_session,
      on_mount: [{Web.UserAuth, :mount_current_path}, {Web.UserAuth, :mount_current_user}] do
      live "/login", UserLoginLive, :new
      live "/login/code", UserLoginCodeLive, :new
    end
  end

  # The plug runs on the first page load, so a logged-out visit remembers the page and
  # logging in returns to it. The on_mount checks cover live navigation.
  scope "/", Web do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user_session,
      on_mount: [{Web.UserAuth, :mount_current_path}, {Web.UserAuth, :ensure_authenticated}] do
      live "/account", AccountLive
    end

    live_session :require_admin_session,
      on_mount: [
        {Web.UserAuth, :mount_current_path},
        {Web.UserAuth, :ensure_authenticated},
        {Web.UserAuth, :ensure_admin}
      ] do
      live "/admin", AdminDashboardLive
      live "/admin/admins", Admin.AdminCollectionLive
      live "/admin/events", Admin.EventCollectionLive
      live "/admin/orgs", Admin.OrganizationCollectionLive
      live "/admin/orgs/new", Admin.OrganizationLive, :new
      live "/admin/orgs/:id", Admin.OrganizationLive, :edit
    end

    live_session :require_current_team_session,
      on_mount: [
        {Web.UserAuth, :mount_current_path},
        {Web.UserAuth, :ensure_authenticated},
        {Web.UserAuth, :ensure_authorized_team_subdomain}
      ] do
      live "/teams/:subdomain", TeamDashboardLive
      live "/teams/:subdomain/activities", ActivityCollectionLive
      live "/teams/:subdomain/activities/:id", ActivityLive
      live "/teams/:subdomain/activities/:id/attendance", ActivityAttendanceLive
      live "/teams/:subdomain/activities/:id/mileage", ActivityMileageLive
      live "/teams/:subdomain/activities/:id/take-attendance", ActivityTakeAttendanceLive
      live "/teams/:subdomain/members", MemberCollectionLive
      live "/teams/:subdomain/members/:id", MemberLive
      live "/teams/:subdomain/members/:id/groups", MemberGroupsLive
      live "/teams/:subdomain/members/:id/qualifications", MemberQualificationsLive
      live "/teams/:subdomain/members/:id/card", MemberCardLive
      live "/teams/:subdomain/groups", GroupCollectionLive
      live "/teams/:subdomain/groups/:id", GroupLive
      live "/teams/:subdomain/groups/:id/review", GroupReviewLive
      live "/teams/:subdomain/qualifications", QualificationCollectionLive
      live "/teams/:subdomain/qualifications/:id", QualificationLive
      live "/teams/:subdomain/tax-credit-letters", TaxCreditLetterCollectionLive
      live "/teams/:subdomain/tax-credit-letters/:id", TaxCreditLetterLive
      live "/teams/:subdomain/settings", Settings.TeamLive
      live "/teams/:subdomain/settings/cards", Settings.CardsLive
      live "/teams/:subdomain/settings/managers", TeamManagersLive
    end

    scope "/teams/:subdomain" do
      pipe_through :require_authorized_team_subdomain

      get "/members/:id/image", MemberController, :image
      get "/members/:id/card/apple-wallet", MemberCardController, :pass
      get "/members/:id/card/google-wallet", MemberCardController, :google_pass
      get "/tax-credit-letters/:id/pdf", TaxCreditLetterController, :show
    end
  end

  # No route to the MCP endpoint (Web.MCPController) until teams can opt in
  # with their own tokens: #28.
end
