defmodule Web.MemberPagesTest do
  # Every page a member reaches, opened as a member and as a team admin viewing as one
  # (#440). Each link to a team page opens for them, and each event a member's control
  # sends reaches the page, so a button never does nothing. Viewing as a member, a
  # control that saves is refused with a message instead (Web.ViewAsControllerTest). The
  # rules are in docs/members.md, "Opening a page to members".
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: sam, user: sam_user} = member_with_login_fixture(%{name: "Sam Rivera"})

    team =
      team
      |> Ecto.Changeset.change(id_cards_enabled: true, certificates_enabled: true)
      |> Repo.update!()

    admin = App.AccountsFixtures.user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})

    avery = member_fixture(team, %{name: "Avery Chen"})
    group_member_fixture(group_fixture(team, %{title: "Callout"}), avery)
    certificate_award_fixture(team, avery)
    away_period_fixture(avery, Date.add(Date.utc_today(), -5), Date.add(Date.utc_today(), 30))
    equipment_item_fixture(team, %{member_id: avery.id})

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    past = activity_fixture(team, %{started_at: DateTime.add(now, -3, :day)})
    coming = activity_fixture(team, %{started_at: DateTime.add(now, 3, :day)})

    # Two on now, so Take attendance lists them rather than opening one's scanner.
    [on_now, _other] =
      for _ <- 1..2,
          do: activity_fixture(team, %{started_at: now, finished_at: DateTime.add(now, 2, :hour)})

    for member <- [sam, avery] do
      attendance_fixture(past, member, %{
        status: "attending",
        started_at: past.started_at,
        finished_at: DateTime.add(past.started_at, 2, :hour)
      })
    end

    attendance_fixture(coming, sam, %{status: "requested"})
    chore = chore_fixture(sam, chore_category_fixture(team))
    tax_credit_letter_fixture(sam)
    certificate = certificate_fixture(sam, qualification_fixture(team))

    viewing_as =
      build_conn()
      |> log_in_user(admin)
      |> post(~p"/teams/#{team}/members/#{sam}/view-as")
      |> recycle()

    s = team.subdomain

    pages = [
      "/teams/#{s}",
      "/teams/#{s}/activities",
      "/teams/#{s}/activities/#{past.id}",
      "/teams/#{s}/activities/#{coming.id}",
      "/teams/#{s}/take-attendance",
      "/teams/#{s}/activities/#{on_now.id}/take-attendance",
      "/teams/#{s}/members",
      "/teams/#{s}/members/#{avery.id}",
      "/teams/#{s}/members/#{avery.id}/qualifications",
      "/teams/#{s}/members/#{avery.id}/groups",
      "/teams/#{s}/milestones",
      "/teams/#{s}/me",
      "/teams/#{s}/me/activities",
      "/teams/#{s}/me/certificates/new",
      "/teams/#{s}/me/certificates/#{certificate.id}/edit",
      "/teams/#{s}/me/chores",
      "/teams/#{s}/me/chores/new",
      "/teams/#{s}/me/chores/#{chore.id}/edit",
      "/teams/#{s}/me/details"
    ]

    %{
      member: log_in_user(conn, sam_user),
      viewing_as: viewing_as,
      pages: pages,
      team: team,
      chore: chore
    }
  end

  test "the sweep opens every LiveView a member reaches", %{pages: pages} do
    swept = MapSet.new(pages, &route(&1).route)

    live_views =
      for path <- Web.RouterTest.member_route_paths(),
          %{metadata: %{phoenix_live_view: _}} <- [route_template(path)],
          into: MapSet.new(),
          do: path

    assert swept == live_views
  end

  for who <- [:member, :viewing_as] do
    test "as #{who}: every team link opens for a member", context do
      conn = Map.fetch!(context, unquote(who))
      found = for path <- context.pages, href <- links(conn, path), do: {path, href}

      for {path, href} <- found do
        assert reachable?(href), "#{path} links to #{href}, which a member can't open"
      end

      # The side navigation alone has 6 on every page, so few means the sweep saw nothing.
      assert length(found) > 100
    end
  end

  test "every control's event on a member's page reaches the page", %{member: conn} = context do
    for path <- context.pages do
      view = route(path).view

      for event <- conn |> document(path) |> events() do
        assert Web.UserAuth.page_access(view) == :member or
                 event in Web.UserAuth.view_events(view) or
                 event in Web.UserAuth.member_events(view),
               "#{path} offers #{inspect(event)}, which #{inspect(view)} refuses a member"
      end
    end
  end

  # A form's change only redraws it, so view as gets it too, without the refusal on
  # every keystroke. Take attendance's name box picks on change, a member action.
  test "viewing as a member, every form's change reaches the page",
       %{viewing_as: conn} = context do
    for path <- context.pages do
      view = route(path).view

      for event <- conn |> document(path) |> events(["phx-change"]) do
        assert event in Web.UserAuth.view_events(view) or
                 event in Web.UserAuth.member_events(view),
               "#{path} offers #{inspect(event)}, which #{inspect(view)} refuses view as"
      end
    end
  end

  defp document(conn, path) do
    {:ok, lv, _html} = live(conn, path)
    lv |> render() |> LazyHTML.from_fragment()
  end

  # Links to team pages; the banner's Stop viewing is the team admin's, and a link with
  # a method is a form post.
  defp links(conn, path) do
    for attrs <- conn |> document(path) |> attributes("a[href]"),
        href = attrs["href"],
        String.starts_with?(href, "/teams/"),
        attrs["data-method"] == nil,
        do: href |> URI.parse() |> Map.fetch!(:path)
  end

  # Events the page's handle_event gets: a control's own event, or a JS command's push,
  # unless it targets a component, which handles it and checks for itself.
  defp events(doc, names \\ ["phx-click", "phx-submit", "phx-change"]) do
    for attrs <- attributes(doc, Enum.map_join(names, ", ", &"[#{&1}]")),
        attrs["phx-target"] == nil,
        name <- names,
        value = attrs[name],
        event <- event_names(value),
        not String.starts_with?(event, "lv:"),
        uniq: true,
        do: event
  end

  defp event_names(nil), do: []

  defp event_names("[" <> _ = js) do
    for ["push", %{"event" => event} = args] <- Jason.decode!(js),
        args["target"] == nil,
        do: event
  end

  defp event_names(event), do: [event]

  defp attributes(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attributes() |> Enum.map(&Map.new/1)

  defp reachable?(path) do
    case route(path) do
      %{route: route} -> route in Web.RouterTest.member_route_paths()
      _none -> false
    end
  end

  defp route(path) do
    case Phoenix.Router.route_info(Web.Router, "GET", path, "www.example.com") do
      %{phoenix_live_view: {view, _action, _opts, _extra}} = info -> Map.put(info, :view, view)
      :error -> nil
      info -> info
    end
  end

  defp route_template(path), do: Enum.find(Web.Router.__routes__(), &(&1.path == path))
end
