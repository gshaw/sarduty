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

  # Google Wallet's save and delete callbacks (#389), set on the pass class. Google signs
  # the body itself; no session or CSRF token.
  scope "/wallet/google", Web do
    post "/", GoogleWalletController, :callback
  end

  # The MCP endpoint (#28): a bearer token only, so no session, CSRF token, or Accept
  # check. The token decides the team. docs/mcp.md.
  scope "/teams/:subdomain", Web do
    post "/mcp", MCPController, :post
    get "/mcp", MCPController, :get
    delete "/mcp", MCPController, :delete
  end

  # A mail app's one-click unsubscribe from a reminder (RFC 8058, #444): it posts with no
  # session or CSRF token. The signed token is the only access. Its page is the GET below.
  scope "/reminders", Web do
    post "/:token", InvitationRemindersController, :unsubscribe
  end

  # Map images (Web.MapImage). Signed keys, no session: the style guide shows one too.
  scope "/maps", Web do
    get "/:key", MapImageController, :show
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
      live "/terms", TermsLive
      live "/privacy", PrivacyLive
      live "/signup", TeamSignupLive
      # A reminder email's links (#444): replying, and turning reminders off. No login.
      live "/replies/:token", ReplyLinkLive
      live "/reminders/:token", InvitationRemindersLive
    end

    # Send reply on a reminder's reply page (#488).
    post "/replies/:token", ReplyLinkController, :create
    # Add to calendar on the reply page: the reply link's activity as an .ics file.
    get "/replies/:token/calendar", ActivityCalendarController, :reply

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
      live "/admin/teams/:id", Admin.TeamLive
      live "/admin/admins", Admin.AdminCollectionLive
      live "/admin/events", Admin.EventCollectionLive
      live "/admin/mcp", Admin.MCPLive
      live "/admin/orgs", Admin.OrganizationCollectionLive
      live "/admin/orgs/new", Admin.OrganizationNewLive
    end

    # An organization's space (#512): its organization admins and SAR Duty admins. Its
    # pages show each team's totals, never its people. The verify host's own /orgs/:slug
    # is in the host-matched scope above, so it never reaches here.
    live_session :org_session,
      on_mount: [
        {Web.UserAuth, :mount_current_path},
        {Web.UserAuth, :ensure_authenticated},
        {Web.UserAuth, :ensure_org_access}
      ] do
      live "/orgs/:slug", Org.TeamCollectionLive
      live "/orgs/:slug/teams/new", Org.TeamNewLive
      live "/orgs/:slug/teams/:subdomain", Org.TeamLive
      live "/orgs/:slug/settings", Org.SettingsLive
      live "/orgs/:slug/settings/admins", Org.AdminsLive
      live "/orgs/:slug/settings/hours-tags", Org.HoursTagsLive
    end

    # Every team page, in one live_session so moving between them doesn't reload (#406).
    # Each page says who opens it: team admins unless it says otherwise (Web), and a
    # member's own pages, /me, only the member. test/web/router_test.exs lists what
    # members reach.
    live_session :team_session,
      session: {Web.VerifyLimit, :session, []},
      on_mount: [
        {Web.UserAuth, :mount_current_path},
        {Web.UserAuth, :ensure_authenticated},
        {Web.UserAuth, :ensure_team_access}
      ] do
      live "/teams/:subdomain", TeamDashboardLive
      live "/teams/:subdomain/activities", ActivityCollectionLive
      # Teams print a QR code of this one (#475), so it can't move: docs/urls.md.
      live "/teams/:subdomain/take-attendance", TakeAttendanceLive
      live "/teams/:subdomain/activities/new", ActivityFormLive, :new
      live "/teams/:subdomain/activities/:id", ActivityLive
      live "/teams/:subdomain/activities/:id/edit", ActivityFormLive, :edit
      live "/teams/:subdomain/activities/:id/mileage", ActivityMileageLive
      live "/teams/:subdomain/activities/:id/history", ActivityHistoryLive
      live "/teams/:subdomain/activities/:id/attendance", ActivityAttendanceLive
      live "/teams/:subdomain/activities/:id/take-attendance", ActivityTakeAttendanceLive
      live "/teams/:subdomain/activities/:id/equipment", ActivityEquipmentLive
      live "/teams/:subdomain/activities/:id/templates", ActivityTemplateLive
      live "/teams/:subdomain/activities/:id/members", ActivityAddMembersLive
      live "/teams/:subdomain/activities/:id/reminders", ActivitySendRemindersLive
      live "/teams/:subdomain/activities/:id/updates", ActivitySendUpdateLive
      live "/teams/:subdomain/activities/:id/tags", ActivityTagsLive
      live "/teams/:subdomain/templates", TemplateCollectionLive
      live "/teams/:subdomain/templates/new", TemplateFormLive, :new
      live "/teams/:subdomain/templates/:id", TemplateFormLive, :edit
      live "/teams/:subdomain/equipment", EquipmentCollectionLive
      live "/teams/:subdomain/equipment/new", EquipmentItemFormLive, :new
      live "/teams/:subdomain/equipment/:id", EquipmentItemLive
      live "/teams/:subdomain/equipment/:id/edit", EquipmentItemFormLive, :edit
      live "/teams/:subdomain/members", MemberCollectionLive
      live "/teams/:subdomain/members/new", MemberFormLive, :new
      live "/teams/:subdomain/members/:id", MemberLive
      live "/teams/:subdomain/members/:id/edit", MemberFormLive, :edit
      live "/teams/:subdomain/members/:id/groups", MemberGroupsLive
      live "/teams/:subdomain/members/:id/equipment", MemberEquipmentLive
      live "/teams/:subdomain/members/:id/qualifications", MemberQualificationsLive
      live "/teams/:subdomain/members/:id/standing", MemberStandingLive
      live "/teams/:subdomain/members/:id/card", MemberCardLive
      live "/teams/:subdomain/members/:id/history", MemberHistoryLive
      live "/teams/:subdomain/groups", GroupCollectionLive
      live "/teams/:subdomain/groups/new", TitledRecordFormLive, :new_group
      live "/teams/:subdomain/groups/:id", GroupLive
      live "/teams/:subdomain/groups/:id/edit", TitledRecordFormLive, :edit_group
      live "/teams/:subdomain/groups/:id/review", GroupReviewLive
      live "/teams/:subdomain/groups/:id/rules/:rule_id", GroupRuleLive
      live "/teams/:subdomain/qualifications", QualificationCollectionLive
      live "/teams/:subdomain/endorsements", EndorsementCollectionLive
      live "/teams/:subdomain/endorsements/new", EndorsementFormLive, :new
      live "/teams/:subdomain/endorsements/:id", EndorsementFormLive, :edit
      live "/teams/:subdomain/qualifications/new", TitledRecordFormLive, :new_qualification
      live "/teams/:subdomain/qualifications/:id", QualificationLive
      live "/teams/:subdomain/qualifications/:id/edit", TitledRecordFormLive, :edit_qualification
      live "/teams/:subdomain/milestones", MilestoneCollectionLive
      live "/teams/:subdomain/certificates", CertificateCollectionLive
      live "/teams/:subdomain/certificates/:id", CertificateLive
      live "/teams/:subdomain/chores", ChoreCollectionLive
      live "/teams/:subdomain/whiteboard", WhiteboardLive
      live "/teams/:subdomain/whiteboard/new", WhiteboardNoteFormLive, :new
      live "/teams/:subdomain/whiteboard/:id/edit", WhiteboardNoteFormLive, :edit
      live "/teams/:subdomain/chores/:id", ChoreLive
      live "/teams/:subdomain/chores/:id/edit", ChoreFormLive
      live "/teams/:subdomain/tax-credit-letters", TaxCreditLetterCollectionLive
      live "/teams/:subdomain/tax-credit-letters/:id", TaxCreditLetterLive
      live "/teams/:subdomain/settings", Settings.TeamLive
      live "/teams/:subdomain/settings/managers", TeamManagersLive
      live "/teams/:subdomain/settings/members", Settings.MembersLive
      live "/teams/:subdomain/settings/member-logins", Settings.MemberLoginsLive
      live "/teams/:subdomain/settings/letters", Settings.LettersLive
      live "/teams/:subdomain/settings/hours-tags", Settings.HoursTagsLive
      live "/teams/:subdomain/settings/places", Settings.PlaceCollectionLive
      live "/teams/:subdomain/settings/places/new", Settings.PlaceFormLive, :new
      live "/teams/:subdomain/settings/places/:id", Settings.PlaceFormLive, :edit
      live "/teams/:subdomain/settings/chore-categories", Settings.ChoreCategoryCollectionLive
      live "/teams/:subdomain/settings/chore-categories/new", Settings.ChoreCategoryFormLive, :new

      live "/teams/:subdomain/settings/chore-categories/:id",
           Settings.ChoreCategoryFormLive,
           :edit

      live "/teams/:subdomain/settings/mcp", Settings.MCPLive
      live "/teams/:subdomain/me", MeLive
      live "/teams/:subdomain/me/activities", MeActivitiesLive
      live "/teams/:subdomain/me/chores", MeChoresLive
      live "/teams/:subdomain/me/chores/new", MeChoreFormLive, :new
      live "/teams/:subdomain/me/chores/:id/edit", MeChoreFormLive, :edit
      live "/teams/:subdomain/me/certificates/new", MeCertificateFormLive, :new
      live "/teams/:subdomain/me/certificates/:id/edit", MeCertificateFormLive, :edit
      live "/teams/:subdomain/me/details", MeDetailsLive
    end

    # A member's own downloads (#156). The member is always the person logged in.
    scope "/teams/:subdomain/me" do
      pipe_through :require_team_member

      get "/card/apple-wallet", MeController, :apple_pass
      get "/card/google-wallet", MeController, :google_pass
      get "/tax-credit-letters/:id/pdf", MeController, :tax_credit_letter
      get "/qualifications/:id/certificate", MeController, :certificate
      get "/certificates/:id/file", MeController, :sent_certificate
    end

    # Team routes members reach too, like a LiveView with access: :team.
    scope "/teams/:subdomain" do
      pipe_through :require_team_access

      get "/activities/:id/calendar", ActivityCalendarController, :show
      get "/members/:id/image", MemberController, :image
    end

    scope "/teams/:subdomain" do
      pipe_through :require_authorized_team_subdomain

      get "/members/:id/certificates/:award_id", MemberController, :certificate
      get "/certificates/:id/file", CertificateController, :file
      get "/tax-credit-letters/:id/pdf", TaxCreditLetterController, :show
      post "/members/:id/view-as", ViewAsController, :create
      delete "/view-as", ViewAsController, :delete
    end
  end
end
