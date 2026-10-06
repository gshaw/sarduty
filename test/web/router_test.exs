defmodule Web.RouterTest do
  # Guardrails for URLs (#153). The rules are in docs/urls.md.
  use ExUnit.Case, async: true

  alias Phoenix.Router

  # Every top-level path on the main site. A new one fails here until it's added on
  # purpose: a fixed word at the top could block a future section, and one under
  # /teams/ or /orgs/ would block a team or organization with that name.
  @main_top_level ~w(teams orgs admin account signup login logout s attendance wallet styles)
  @verify_top_level ["orgs", ":code", "*path"]

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
    {"GET", "/s/abc123", Web.ShortLinkController, :show},
    {"GET", "/attendance/token", Web.AttendanceLinkLive, nil},
    {"GET", "/teams/nsr/logo", Web.TeamController, :logo}
  ]

  @pinned_verify [
    {"GET", "/K7Q4-M2XA", Web.VerifyLive, nil},
    {"GET", "/K7Q4-M2XA/photo", Web.MemberCardController, :photo},
    {"GET", "/K7Q4-M2XA/banner", Web.MemberCardController, :banner},
    {"GET", "/orgs/nsr", Web.VerifyLive, nil}
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

  # Routes in the verify site's scope: its LiveView, card images, and the catch-all.
  defp verify_route?(%{metadata: %{phoenix_live_view: {Web.VerifyLive, _, _, _}}}), do: true
  defp verify_route?(%{plug: Web.VerifyController}), do: true

  defp verify_route?(%{plug: Web.MemberCardController, plug_opts: action}),
    do: action in [:photo, :banner]

  defp verify_route?(_route), do: false

  defp dev_routes?, do: Application.get_env(:sarduty, :dev_routes, false)
end
