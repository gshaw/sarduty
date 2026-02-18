defmodule Web.Router do
  use Web, :router

  import Web.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :assign_current_user
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
      live "/signup", UserRegistrationLive, :new
      live "/signup/confirm/:token", UserConfirmationLive, :edit
      live "/signup/confirm", UserConfirmationInstructionsLive, :new
      live "/login", UserLoginLive, :new
      live "/login/reset", UserForgotPasswordLive, :new
      live "/login/reset/:token", UserResetPasswordLive, :edit
    end

    post "/login", UserSessionController, :create
    delete "/logout", UserSessionController, :delete
  end

  scope "/", Web do
    pipe_through :browser

    live_session :require_authenticated_user_session,
      on_mount: [{Web.UserAuth, :ensure_authenticated}] do
      live "/settings", SettingsLive
      live "/settings/email", Settings.ChangeEmailLive
      live "/settings/password", Settings.ChangePasswordLive
      live "/settings/confirm_email/:token", SettingsLive
      live "/settings/d4h", Settings.D4HLive
      live "/settings/team", Settings.TeamLive
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
      live "/:subdomain/members", MemberCollectionLive
      live "/:subdomain/members/:id", MemberLive
      live "/:subdomain/qualifications", QualificationCollectionLive
      live "/:subdomain/qualifications/:id", QualificationLive
      live "/:subdomain/tax-credit-letters", TaxCreditLetterCollectionLive
      live "/:subdomain/tax-credit-letters/:id", TaxCreditLetterLive
    end

    scope "/" do
      pipe_through [:require_authenticated_user, :require_authorized_team_subdomain]

      get "/:subdomain/image", TeamController, :image
      get "/:subdomain/members/:id/image", MemberController, :image
      get "/:subdomain/tax-credit-letters/:id/pdf", TaxCreditLetterController, :show
    end
  end
end
