defmodule Web.TransferFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberQualificationAward
  alias App.Model.Transfer
  alias App.Model.TransferAward
  alias App.Model.TransferAwardFile
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{name: "Coast Range SAR"}})
    team = team |> Ecto.Changeset.change(d4h_access_key: "team-key") |> Repo.update!()
    member = member_fixture(team, %{name: "Sam Rivera", email: "sam@example.com"})

    first_aid =
      qualification_award_fixture(qualification_fixture(team, %{title: "First aid"}), member, %{
        starts_at: ~U[2026-07-30 00:00:00Z],
        ends_at: ~U[2029-07-30 00:00:00Z]
      })

    MemberQualificationAward.set_documents([{first_aid.id, 77}])

    gsar =
      qualification_award_fixture(
        qualification_fixture(team, %{title: "Ground search and rescue", organization_owned: true}),
        member,
        %{starts_at: ~U[2020-11-04 00:00:00Z]}
      )

    swiftwater =
      qualification_award_fixture(
        qualification_fixture(team, %{title: "Swiftwater rescue technician"}),
        member,
        %{starts_at: ~U[2023-10-04 00:00:00Z], ends_at: ~U[2026-10-04 00:00:00Z]}
      )

    %{
      conn: log_in_user(conn, user),
      team: team,
      member: member,
      first_aid: first_aid,
      gsar: gsar,
      swiftwater: swiftwater
    }
  end

  defp path(ctx), do: ~p"/teams/#{ctx.team}/members/#{ctx.member.id}/transfers/new"

  defp d4h_award(award),
    do: %{
      "id" => award.d4h_award_id,
      "member" => %{"resourceType" => "Member", "id" => 1},
      "qualification" => %{"id" => 1},
      "startsAt" => award.starts_at && DateTime.to_iso8601(award.starts_at),
      "endsAt" => award.ends_at && DateTime.to_iso8601(award.ends_at)
    }

  # D4H has the member's awards as the copy has them, and First aid's certificate.
  defp stub_d4h(ctx, awards) do
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test_pid, {:d4h, conn.method, conn.request_path})
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
      params = Plug.Conn.fetch_query_params(conn).query_params

      case {conn.method, path} do
        {"GET", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{
            "results" => Enum.map(awards, &d4h_award/1),
            "totalSize" => length(awards)
          })

        {"GET", "/documents"} ->
          results = documents(ctx, params["target_resource_id"])
          Req.Test.json(conn, %{"results" => results, "totalSize" => length(results)})

        {"GET", "/documents/77/download"} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/pdf")
          |> Plug.Conn.send_resp(200, "%PDF-1.7 first aid")
      end
    end)
  end

  defp documents(ctx, d4h_award_id) do
    if d4h_award_id == to_string(ctx.first_aid.d4h_award_id),
      do: [%{"id" => 77, "targetResource" => %{"id" => ctx.first_aid.d4h_award_id}}],
      else: []
  end

  test "the member's page links to it", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/members/#{ctx.member.id}")

    assert has_element?(
             lv,
             "#member-actions-transfer[href='#{path(ctx)}']",
             "Transfer to another team"
           )
  end

  test "lists the awards, with expired ones unchecked", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    assert has_element?(lv, "h1", "Sam Rivera · Transfer to another team")
    assert has_element?(lv, "#transfer-select-#{ctx.first_aid.id}[checked]")
    assert has_element?(lv, "#transfer-select-#{ctx.gsar.id}[checked]")
    refute has_element?(lv, "#transfer-select-#{ctx.swiftwater.id}[checked]")
    assert has_element?(lv, "#transfer-award-#{ctx.swiftwater.id}", "Expired")
    assert has_element?(lv, "#transfer-award-#{ctx.first_aid.id}", "Certificate")
    assert has_element?(lv, "#transfer-award-#{ctx.gsar.id}", "None")
    assert has_element?(lv, "#transfer-award-#{ctx.gsar.id}", "From Nov 3, 2020")
  end

  test "makes the code from D4H now, with the certificate, and opens it", ctx do
    stub_d4h(ctx, [ctx.first_aid, ctx.gsar, ctx.swiftwater])
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    {:ok, lv, _html} =
      lv |> form("#transfer-form") |> render_submit() |> follow_redirect(ctx.conn)

    transfer = Transfer |> Repo.one!() |> Repo.preload(:awards)
    assert transfer.team_id == ctx.team.id
    assert transfer.member_id == ctx.member.id
    assert transfer.member_name == "Sam Rivera"
    assert transfer.member_email == "sam@example.com"
    assert Transfer.status(transfer, DateTime.utc_now()) == :open

    assert [first_aid, gsar] = transfer.awards
    assert first_aid.qualification_title == "First aid"
    assert first_aid.starts_at == ~U[2026-07-30 00:00:00Z]
    assert first_aid.ends_at == ~U[2029-07-30 00:00:00Z]
    assert first_aid.file_name == "First aid.pdf"
    assert first_aid.content_type == "application/pdf"
    assert TransferAwardFile.bytes(first_aid) == "%PDF-1.7 first aid"
    assert gsar.organization_owned
    refute TransferAward.certificate?(gsar)
    assert TransferAwardFile.bytes(gsar) == nil

    assert has_element?(lv, "#transfer-code", Transfer.format_code(transfer))
    assert has_element?(lv, "#transfer-award-#{first_aid.id}", "with its certificate")
    refute has_element?(lv, "#transfer-award-#{gsar.id}", "certificate")

    # Its own team's D4H only, read when the code was made.
    assert_received {:d4h, "GET", "/v3/team/" <> _}
  end

  test "an expired award goes when picked, and says so", ctx do
    stub_d4h(ctx, [ctx.first_aid, ctx.gsar, ctx.swiftwater])
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    lv
    |> form("#transfer-form", %{"award_ids" => ["", to_string(ctx.swiftwater.id)]})
    |> render_change()

    refute has_element?(lv, "#transfer-select-#{ctx.first_aid.id}[checked]")

    {:ok, lv, _html} =
      lv |> form("#transfer-form") |> render_submit() |> follow_redirect(ctx.conn)

    assert [award] = Repo.all(TransferAward)
    assert award.qualification_title == "Swiftwater rescue technician"
    assert has_element?(lv, "#transfer-award-#{award.id}", "expired")
  end

  test "an award D4H no longer has makes no code", ctx do
    stub_d4h(ctx, [ctx.first_aid])
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    html = lv |> form("#transfer-form") |> render_submit()

    assert html =~ "Ground search and rescue has changed since this page opened."
    assert Repo.all(Transfer) == []
  end

  test "nothing selected makes no code", ctx do
    {:ok, lv, _html} = live(ctx.conn, path(ctx))

    lv |> form("#transfer-form", %{"award_ids" => [""]}) |> render_change()

    assert has_element?(lv, "#transfer-make[disabled]")
  end

  test "an open code is linked", ctx do
    stub_d4h(ctx, [ctx.first_aid, ctx.gsar])
    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    lv |> form("#transfer-form") |> render_submit()
    transfer = Repo.one!(Transfer)

    {:ok, lv, _html} = live(ctx.conn, path(ctx))
    assert has_element?(lv, "#transfer-open-#{transfer.id}", Transfer.format_code(transfer))
  end

  test "a member cannot open it" do
    %{team: team, user: user, member: member} = member_with_login_fixture()
    conn = log_in_user(build_conn(), user)

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/members/#{member.id}/transfers/new")
    end
  end

  test "another team's member is not found", ctx do
    other = member_fixture(team_fixture())

    assert_raise Ecto.NoResultsError, fn ->
      live(ctx.conn, ~p"/teams/#{ctx.team}/members/#{other.id}/transfers/new")
    end
  end
end
