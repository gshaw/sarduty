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
      live "/:code", VerifyLive
    end

    get "/:code/photo", MemberCardController, :photo
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

  scope "/", Web do
    pipe_through :browser

    live_session :current_user_session,
      on_mount: [{Web.UserAuth, :mount_current_user}] do
      live "/", HomePageLive
      live "/styles", StyleGuideLive
      live "/login", UserLoginLive, :new
      live "/login/sent", UserLoginSentLive, :new
      live "/login/:token", UserLoginLinkLive, :new
    end

    # The check moved to the verify site. Cards linked here before it, in capitals.
    get "/verify", VerifyController, :to_verify
    get "/verify/:code", VerifyController, :to_verify
    get "/VERIFY/:code", VerifyController, :to_verify

    get "/verify/:code/photo", MemberCardController, :photo
    get "/verify/:code/banner", MemberCardController, :banner
    get "/teams/:subdomain/logo", TeamController, :logo

    post "/login/link", UserSessionController, :request_link
    post "/login", UserSessionController, :create
    delete "/logout", UserSessionController, :delete
  end

  scope "/", Web do
    pipe_through :browser

    live_session :require_authenticated_user_session,
      on_mount: [{Web.UserAuth, :ensure_authenticated}] do
      live "/settings", SettingsLive
      live "/settings/team", Settings.TeamLive
      live "/settings/cards", Settings.CardsLive
    end

    live_session :require_admin_session,
      on_mount: [
        {Web.UserAuth, :ensure_authenticated},
        {Web.UserAuth, :ensure_admin}
      ] do
      live "/admin", AdminDashboardLive
    end

    live_session :require_current_team_session,
      on_mount: [
        {Web.UserAuth, :ensure_authenticated},
        {Web.UserAuth, :ensure_authorized_team_subdomain}
      ] do
      live "/:subdomain", TeamDashboardLive
      live "/:subdomain/activities", ActivityCollectionLive
      live "/:subdomain/activities/:id", ActivityLive
      live "/:subdomain/activities/:id/attendance", ActivityAttendanceLive
      live "/:subdomain/activities/:id/mileage", ActivityMileageLive
      live "/:subdomain/managers", TeamManagersLive
      live "/:subdomain/members", MemberCollectionLive
      live "/:subdomain/members/:id", MemberLive
      live "/:subdomain/members/:id/groups", MemberGroupsLive
      live "/:subdomain/members/:id/qualifications", MemberQualificationsLive
      live "/:subdomain/members/:id/card", MemberCardLive
      live "/:subdomain/groups", GroupCollectionLive
      live "/:subdomain/groups/:id", GroupLive
      live "/:subdomain/groups/:id/review", GroupReviewLive
      live "/:subdomain/qualifications", QualificationCollectionLive
      live "/:subdomain/qualifications/:id", QualificationLive
      live "/:subdomain/tax-credit-letters", TaxCreditLetterCollectionLive
      live "/:subdomain/tax-credit-letters/:id", TaxCreditLetterLive
    end

    scope "/" do
      pipe_through [:require_authenticated_user, :require_authorized_team_subdomain]

      get "/:subdomain/members/:id/image", MemberController, :image
      get "/:subdomain/members/:id/card/pass", MemberCardController, :pass
      get "/:subdomain/members/:id/card/google-pass", MemberCardController, :google_pass
      get "/:subdomain/tax-credit-letters/:id/pdf", TaxCreditLetterController, :show
    end
  end

  # No route to the MCP endpoint (Web.MCPController) until teams can opt in
  # with their own tokens: #28.
end
