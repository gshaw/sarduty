defmodule Web.RouterTest do
  # Guardrails for URLs (#153). The rules are in docs/urls.md.
  use ExUnit.Case, async: true

  alias Phoenix.Router

  # Every top-level path on the main site. A new one fails here until it's added on
  # purpose: a fixed word at the top could block a future section, and one under
  # /teams/ or /orgs/ would block a team or organization with that name.
  @main_top_level ~w(teams orgs admin account signup login logout replies reminders cards wallet styles
                     terms privacy agents agents.md changelog changelog.md maps .well-known
                     security.txt llms.txt csp-reports demo api)
  @verify_top_level [
    "api",
    ".well-known",
    "security.txt",
    "orgs",
    "samples",
    ":code",
    "*path"
  ]

  test "the main site's top-level paths are the allowed ones" do
    allowed = MapSet.new(["" | @main_top_level] ++ if(dev_routes?(), do: ["dev"], else: []))

    top =
      for route <- Web.Router.__routes__(), not verify_route?(route), into: MapSet.new() do
        top_segment(route.path)
      end

    assert MapSet.difference(top, allowed) == MapSet.new()
  end

  test "the verify site's top-level paths are the allowed ones" do
    top =
      for route <- Web.Router.__routes__(), verify_route?(route), into: MapSet.new() do
        top_segment(route.path)
      end

    assert top == MapSet.new(["" | @verify_top_level])
  end

  test "nothing fixed sits directly under /teams/ or /orgs/" do
    for %{path: path} <- Web.Router.__routes__(),
        [section, name | _rest] <- [String.split(path, "/", trim: true)],
        section in ["teams", "orgs"] do
      assert name in [":subdomain", ":slug"], "#{path} would block a team or org named so"
    end
  end

  # Every team route a member who is not a team admin reaches (#406). Team pages are for
  # team admins unless a LiveView says `access: :team` or `:member` (Web). MeController
  # serves a member's own downloads, ActivityCalendarController Add to calendar,
  # MemberController's image the photo on a member's page (#440) and original_image the
  # same photo at full size (#1028), and
  # CertificateController's file a member's own sent certificate (#645).
  # Opening a page to members means changing this list on purpose. Web.TeamScopingTest
  # checks every other team route 404s for a member.
  @member_routes [
    "/teams/:subdomain",
    "/teams/:subdomain/activities",
    "/teams/:subdomain/activities/:id",
    "/teams/:subdomain/activities/:id/calendar",
    "/teams/:subdomain/activities/:id/equipment",
    "/teams/:subdomain/activities/:id/fields",
    "/teams/:subdomain/activities/:id/members",
    # The Members tab's steps (#895): its LiveView, so a member opening one lands on the
    # tab, as nothing on it is offered to them.
    "/teams/:subdomain/activities/:id/members/ask",
    "/teams/:subdomain/activities/:id/members/remove",
    "/teams/:subdomain/activities/:id/members/update",
    "/teams/:subdomain/activities/:id/take-attendance",
    # A form's sign page (#993): only the member a team admin asked to sign opens it.
    "/teams/:subdomain/activities/:id/forms/:form_id/sign",
    "/teams/:subdomain/certificates/:id/edit",
    "/teams/:subdomain/certificates/:id/file",
    "/teams/:subdomain/certificates/new",
    "/teams/:subdomain/chores",
    "/teams/:subdomain/chores/:id/edit",
    "/teams/:subdomain/chores/new",
    "/teams/:subdomain/take-attendance",
    "/teams/:subdomain/whiteboard",
    "/teams/:subdomain/help",
    "/teams/:subdomain/me",
    "/teams/:subdomain/me/activities",
    "/teams/:subdomain/me/address",
    "/teams/:subdomain/me/card/apple-wallet",
    "/teams/:subdomain/me/card/google-wallet",
    "/teams/:subdomain/me/emergency-contacts",
    "/teams/:subdomain/me/fields",
    "/teams/:subdomain/me/mobile",
    "/teams/:subdomain/me/qualifications/:id/certificate",
    "/teams/:subdomain/me/tax-credit-letters/:id/pdf",
    "/teams/:subdomain/members",
    "/teams/:subdomain/members/:id",
    "/teams/:subdomain/members/:id/groups",
    "/teams/:subdomain/members/:id/image",
    "/teams/:subdomain/members/:id/image/original",
    "/teams/:subdomain/members/:id/qualifications",
    "/teams/:subdomain/milestones"
  ]

  test "members reach only the listed team routes" do
    assert Enum.sort(member_routes()) == Enum.sort(@member_routes)
  end

  @doc "The list above, for Web.TeamScopingTest's sweep."
  def member_route_paths, do: @member_routes

  defp member_routes do
    for route <- Web.Router.__routes__(),
        String.starts_with?(route.path, "/teams/:subdomain"),
        member_route?(route),
        do: route.path
  end

  defp member_route?(%{metadata: %{phoenix_live_view: {view, _action, _opts, _extra}}}),
    do: Web.UserAuth.page_access(view) in [:team, :member]

  defp member_route?(%{plug: Web.MemberController, plug_opts: action}),
    do: action in [:image, :original_image]

  defp member_route?(%{plug: Web.CertificateController, plug_opts: action}), do: action == :file

  defp member_route?(%{plug: plug}),
    do: plug in [Web.MeController, Web.ActivityCalendarController]

  # URLs held by devices, printed cards, Google and Apple, and shared links. They must
  # keep working, so a refactor can't move them quietly.
  @pinned [
    {"POST", "/wallet/v1/devices/d/registrations/pass.type/S1", Web.WalletController, :register},
    {"DELETE", "/wallet/v1/devices/d/registrations/pass.type/S1", Web.WalletController,
     :unregister},
    {"GET", "/wallet/v1/devices/d/registrations/pass.type", Web.WalletController,
     :serial_numbers},
    {"GET", "/wallet/v1/passes/pass.type/S1", Web.WalletController, :pass},
    {"POST", "/wallet/v1/log", Web.WalletController, :log},
    {"GET", "/replies/token", Web.ReplyLinkLive, nil},
    {"GET", "/reminders/token", Web.InvitationRemindersLive, nil},
    # Every ID card email holds it (#952).
    {"GET", "/cards/token", Web.CardLinkLive, nil},
    {"GET", "/cards/token/apple-wallet", Web.CardLinkController, :apple_pass},
    {"GET", "/cards/token/google-wallet", Web.CardLinkController, :google_pass},
    {"POST", "/reminders/token", Web.InvitationRemindersController, :unsubscribe},
    {"GET", "/teams/nsr/logo", Web.TeamController, :logo},
    {"GET", "/teams/nsr/take-attendance", Web.TakeAttendanceLive, nil},
    {"POST", "/teams/nsr/mcp", Web.MCPController, :post},
    # Agents keep these from their first connection (#761).
    {"GET", "/.well-known/oauth-protected-resource/teams/nsr/mcp", Web.OAuthController,
     :resource_metadata},
    {"GET", "/.well-known/oauth-authorization-server/teams/nsr", Web.OAuthController,
     :server_metadata},
    {"POST", "/teams/nsr/oauth/register", Web.OAuthController, :register},
    {"POST", "/teams/nsr/oauth/token", Web.OAuthController, :token},
    {"GET", "/teams/nsr/oauth/authorize", Web.AgentAuthorizeLive, nil}
  ]

  @pinned_verify [
    {"GET", "/K7Q4M-2XA9H", Web.VerifyLive, nil},
    {"GET", "/K7Q4M-2XA9H/photo", Web.MemberCardController, :photo},
    {"GET", "/K7Q4M-2XA9H/banner", Web.MemberCardController, :banner},
    {"GET", "/orgs/nsr", Web.VerifyLive, nil},
    # A published PDF's verify code (#970).
    {"GET", "/K7Q4M-2XA9H-VB3TN", Web.VerifyLive, nil},
    # Apps that scan cards hold it (#299).
    {"GET", "/api/v1/cards/K7Q4M-2XA9H", Web.CardApiController, :show}
  ]

  test "pinned URLs on the main site still route" do
    for {verb, path, module, action} <- @pinned do
      assert target(verb, path, "sarduty.com") == {module, action}, "#{verb} #{path}"
    end
  end

  test "pinned URLs on the verify site still route" do
    for {verb, path, module, action} <- @pinned_verify do
      assert target(verb, path, "verify.sarduty.com") == {module, action}, "#{verb} #{path}"
    end
  end

  defp target(verb, path, host) do
    case Router.route_info(Web.Router, verb, path, host) do
      %{phoenix_live_view: {live_view, _action, _opts, _extra}} -> {live_view, nil}
      %{plug: plug, plug_opts: action} -> {plug, action}
      :error -> :error
    end
  end

  defp top_segment(path), do: path |> String.split("/", trim: true) |> List.first("")

  # Routes in the verify site's scope: its LiveView, card images, the JSON check,
  # security.txt, and the catch-all.
  defp verify_route?(%{metadata: %{phoenix_live_view: {Web.VerifyLive, _, _, _}}}), do: true
  defp verify_route?(%{metadata: %{phoenix_live_view: {Web.VerifyLetterLive, _, _, _}}}), do: true

  defp verify_route?(%{metadata: %{phoenix_live_view: {Web.VerifySamplesLive, _, _, _}}}),
    do: true

  defp verify_route?(%{plug: Web.VerifyController}), do: true
  defp verify_route?(%{plug: Web.CardApiController}), do: true

  defp verify_route?(%{plug: Web.MemberCardController, plug_opts: action}),
    do: action in [:photo, :banner]

  defp verify_route?(_route), do: false

  # Search vs agents (#824). Every route is hidden from search, behind a login, or public,
  # and exactly one. Hidden routes send X-Robots-Tag: noindex through the :noindex
  # pipeline; public ones never do. robots.txt blocks nothing either way.
  @hidden_prefixes ~w(/wallet/ /replies/ /reminders/ /cards/ /maps/ /.well-known/oauth- /csp-reports
                       /demo/open /api/)
  @hidden_team_routes ~w(/teams/:subdomain/mcp /teams/:subdomain/oauth/register
                         /teams/:subdomain/oauth/token)

  @public_routes [
    "/",
    "/.well-known/security.txt",
    "/agents",
    "/agents.md",
    "/agents/id-cards",
    "/agents/id-cards.md",
    "/agents/demo",
    "/agents/demo.md",
    "/agents/reports",
    "/agents/reports.md",
    "/changelog",
    "/changelog.md",
    "/demo",
    "/llms.txt",
    "/login",
    "/login/code",
    "/login/passkey",
    "/login/passkey/options",
    "/logout",
    "/orgs/:slug/logo",
    "/privacy",
    "/security.txt",
    "/signup",
    "/styles",
    "/styles/:page",
    "/teams/:subdomain/logo",
    "/terms"
  ]

  test "every route is hidden from search, behind a login, or public" do
    for route <- Web.Router.__routes__(), not String.starts_with?(route.path, "/dev/") do
      groups = [hidden: hidden?(route), logged_in: logged_in?(route), public: public?(route)]
      found = for {group, true} <- groups, do: group
      noindex? = :noindex in pipe_through(route)

      case found do
        [:hidden] -> assert noindex?, "#{route.verb} #{route.path} must pipe through :noindex"
        [:public] -> refute noindex?, "#{route.verb} #{route.path} is public: no :noindex"
        [:logged_in] -> :ok
        _ -> flunk("classify #{route.verb} #{route.path} as public or hidden (#{inspect(found)})")
      end
    end
  end

  test "every listed public route exists" do
    paths = MapSet.new(Web.Router.__routes__(), & &1.path)
    assert Enum.reject(@public_routes, &(&1 in paths)) == []
  end

  defp hidden?(route) do
    verify_route?(route) or route.path in @hidden_team_routes or
      Enum.any?(@hidden_prefixes, &String.starts_with?(route.path, &1))
  end

  defp logged_in?(route), do: :require_authenticated_user in pipe_through(route)

  # __routes__ leaves out the pipelines, so match a path built from the route's own.
  defp pipe_through(route) do
    host = if verify_route?(route), do: "verify.sarduty.com", else: "sarduty.com"

    path =
      route.path
      |> String.split("/")
      |> Enum.map_join("/", &sample_segment/1)

    verb = route.verb |> Atom.to_string() |> String.upcase()
    %{route: matched, pipe_through: pipes} = Router.route_info(Web.Router, verb, path, host)
    assert matched == route.path, "#{verb} #{path} on #{host} reached #{matched}"
    pipes
  end

  defp public?(route), do: not verify_route?(route) and route.path in @public_routes

  defp sample_segment(":" <> _param), do: "x"
  # Deep enough to pass /:code and /:code/photo.
  defp sample_segment("*" <> _glob), do: "x/y/z"
  defp sample_segment(segment), do: segment

  defp dev_routes?, do: Application.get_env(:sarduty, :dev_routes, false)
end
