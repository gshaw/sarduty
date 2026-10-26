defmodule Web.CertificateLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Model.MemberQualificationAward
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team
      |> Ecto.Changeset.change(
        member_logins: true,
        certificates_enabled: true,
        d4h_access_key: "team-key"
      )
      |> Repo.update!()

    # The page reads D4H's awards as it opens: none yet.
    stub_d4h()
    member = member_fixture(team, %{name: "Sam Rivera"})
    qualification = qualification_fixture(team, %{title: "Standard First Aid"})
    certificate = certificate_fixture(member, qualification)

    %{
      conn: log_in_user(conn, user),
      team: team,
      member: member,
      qualification: qualification,
      certificate: certificate
    }
  end

  defp stub_d4h do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      case {conn.method, String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")} do
        {"GET", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        {"POST", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{
            "id" => 300,
            "member" => %{"resourceType" => "Member", "id" => 1},
            "qualification" => %{"id" => 1}
          })

        {"POST", "/documents"} ->
          Req.Test.json(conn, %{"id" => 900, "targetResource" => %{"id" => 300}})
      end
    end)
  end

  test "waiting certificates are counted in the side navigation and listed", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates")
    assert has_element?(lv, "#side-nav-certificates[aria-current=page]", "1")
    assert has_element?(lv, "#certificates-view-waiting", "1")
    assert has_element?(lv, "#certificate-#{ctx.certificate.id}", "Sam Rivera")
    assert has_element?(lv, "#certificate-#{ctx.certificate.id}", "Oct 18, 2026 to Oct 18, 2029")

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
    assert has_element?(lv, "#attention-certificates", "1 certificate to accept")

    assert has_element?(
             lv,
             ~s{#attention-certificates a[href="/teams/#{ctx.team.subdomain}/certificates"]}
           )
  end

  test "a team admin sees the PDF in a frame without a sandbox attribute, and accepts it",
       ctx do
    stub_d4h()
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}")
    file = ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}/file"
    assert has_element?(lv, "iframe#certificate-pdf[src^='#{file}?v=']")
    refute has_element?(lv, "#certificate-rotate-left")
    refute has_element?(lv, "iframe[sandbox]")
    assert has_element?(lv, "#certificate-latest", "None")

    {:ok, lv, _html} =
      lv
      |> form("#accept-form",
        certificate: %{qualification_id: ctx.qualification.id, confirmed: true}
      )
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert render(lv) =~ "Accepted Standard First Aid for Sam Rivera."
    assert %{status: :accepted} = Repo.reload!(ctx.certificate)
    assert %{d4h_document_id: 900} = award = MemberQualificationAward.get_by(d4h_award_id: 300)

    # Once D4H has no file on the award, the page says so, not that it was declined.
    award |> Ecto.Changeset.change(d4h_document_id: nil) |> Repo.update!()
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}")
    assert has_element?(lv, "#certificate-file-gone", "when the certificate was accepted")
    assert has_element?(lv, "#certificate-fix", "Fix the award in D4H.")
  end

  test "with no qualification picked, the team admin picks one and checks it", ctx do
    wfa =
      qualification_fixture(ctx.team, %{title: "Wilderness First Aid", expires_months_default: 36})

    certificate =
      certificate_fixture(ctx.member, ctx.qualification, %{
        qualification_id: nil,
        ends_on: nil,
        note: "The 40-hour course."
      })

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{certificate.id}")
    assert has_element?(lv, "h1", "Certificate from Sam Rivera")
    assert has_element?(lv, "#certificate-note", "The 40-hour course.")

    assert has_element?(
             lv,
             "#accept-form",
             "Sam did not select one. Read it from the certificate."
           )

    # Picking one fills in its expiry, and the box names what goes.
    lv |> form("#accept-form", certificate: %{qualification_id: wfa.id}) |> render_change()
    assert has_element?(lv, "#certificate_ends_on[value='2029-10-18']")
    assert has_element?(lv, "#accept-form", "New for Sam: no award of it yet.")

    assert has_element?(
             lv,
             "label[for=certificate_confirmed]",
             "It is Wilderness First Aid, Oct 18, 2026 to Oct 18, 2029."
           )

    html = lv |> form("#accept-form", certificate: %{qualification_id: wfa.id}) |> render_submit()
    assert html =~ "Check the certificate, then select the box"
    assert %{status: :waiting, qualification_id: nil} = Repo.reload!(certificate)

    # A box selected for one qualification clears when another is picked.
    values = %{qualification_id: wfa.id, confirmed: true}
    lv |> form("#accept-form", certificate: values) |> render_change()
    assert has_element?(lv, "#certificate_confirmed[checked]")

    lv
    |> form("#accept-form", certificate: %{values | qualification_id: ctx.qualification.id})
    |> render_change()

    refute has_element?(lv, "#certificate_confirmed[checked]")
  end

  test "dates that look wrong are a warning, and an old certificate a past award", ctx do
    wfa =
      qualification_fixture(ctx.team, %{title: "Wilderness First Aid", expires_months_default: 36})

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}")
    refute has_element?(lv, "#certificate-date-warnings")

    values = %{qualification_id: wfa.id, starts_on: "2099-10-18", ends_on: "2100-10-18"}
    lv |> form("#accept-form", certificate: values) |> render_change()
    assert has_element?(lv, "#certificate-date-warnings", "The start is after today.")

    assert has_element?(
             lv,
             "#certificate-date-warnings",
             "Wilderness First Aid lasts 3 years. These dates are 1 year apart."
           )

    values = %{values | starts_on: "2007-06-26", ends_on: "2010-06-26"}
    lv |> form("#accept-form", certificate: values) |> render_change()
    refute has_element?(lv, "#certificate-date-warnings")
    assert has_element?(lv, "#accept-form", "Already expired. It goes on record as a past award.")
  end

  test "a team admin declines it with a reason the member sees", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}")
    assert lv |> form("#decline-form", decline: %{reason: ""}) |> render_submit() =~ "Enter why"

    {:ok, _lv, _html} =
      lv
      |> form("#decline-form", decline: %{reason: "This is for AST 2."})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert %{status: :declined, decline_reason: "This is for AST 2."} =
             Repo.reload!(ctx.certificate)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}")
    assert has_element?(lv, "#certificate-file-gone")
    refute has_element?(lv, "#accept-form")
  end

  test "a team admin turns a sideways photo before accepting it", ctx do
    photo =
      certificate_fixture(ctx.member, ctx.qualification, %{
        file_name: "scan.jpg",
        content_type: "image/jpeg"
      })

    CertificateFile.put!(photo, 40 |> Image.new!(30) |> Image.write!(:memory, suffix: ".jpg"))
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{photo.id}")
    src = image_src(lv)

    lv |> element("#certificate-rotate-left") |> render_click()

    image = photo |> CertificateFile.bytes() |> Image.from_binary!()
    assert {Image.width(image), Image.height(image)} == {30, 40}
    refute image_src(lv) == src

    # Decided since the page opened: it opens again, saying so.
    photo |> Ecto.Changeset.change(status: :declined) |> Repo.update!()
    path = ~p"/teams/#{ctx.team}/certificates/#{photo.id}"

    {:ok, lv, _html} =
      lv
      |> element("#certificate-rotate-right")
      |> render_click()
      |> follow_redirect(ctx.conn, path)

    assert render(lv) =~ "Another team admin has decided this certificate."
  end

  defp image_src(lv) do
    [_match, src] = Regex.run(~r/src="([^"]+)"/, lv |> element("#certificate-image") |> render())
    src
  end

  test "the file is served sandboxed, and only through its team", ctx do
    conn = get(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}/file")
    assert conn.resp_body == "%PDF-1.7\n"
    assert get_resp_header(conn, "content-type") == ["application/pdf"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox"]

    other_team = member_logins_team_fixture()

    other =
      certificate_fixture(member_fixture(other_team), qualification_fixture(other_team))

    assert_error_sent 404, fn ->
      get(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{other.id}/file")
    end
  end

  test "search finds a certificate by its member", ctx do
    hits = Web.Search.run(ctx.team, "sam", team_admin?: true, member?: false)
    assert %{kind: :certificate, hits: [hit]} = Enum.find(hits, &(&1.kind == :certificate))
    assert hit.path == ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}"

    hits = Web.Search.run(ctx.team, "sam", team_admin?: false, member?: true)
    refute Enum.any?(hits, &(&1.kind == :certificate))
    assert Repo.aggregate(Certificate, :count) == 1
  end

  # D4H with Sam's First Aid from the certificate's start, with `documents` on it. D4H
  # keeps the dates at midnight UTC: Oct 17 on the team's clock.
  defp stub_existing(ctx, documents) do
    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")
      if conn.method == "POST", do: send(test_pid, {:post, path})

      case {conn.method, path} do
        {"GET", "/member-qualification-awards"} ->
          Req.Test.json(conn, %{
            "results" => [
              %{
                "id" => 77,
                "member" => %{"resourceType" => "Member", "id" => ctx.member.d4h_member_id},
                "qualification" => %{"id" => ctx.qualification.d4h_qualification_id},
                "startsAt" => "2026-10-18T00:00:00.000Z",
                "endsAt" => "2029-10-18T00:00:00.000Z"
              }
            ],
            "totalSize" => 1
          })

        {"GET", "/documents"} ->
          Req.Test.json(conn, %{"results" => documents, "totalSize" => length(documents)})

        {"POST", "/documents"} ->
          Req.Test.json(conn, %{"id" => 901, "targetResource" => %{"id" => 77}})
      end
    end)
  end

  test "D4H has the award without a certificate: Attach certificate puts the file on it",
       ctx do
    stub_existing(ctx, [])
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}")

    assert has_element?(
             lv,
             "#certificate-existing",
             "from Oct 18, 2026, with no certificate"
           )

    assert has_element?(lv, "#certificate-accept", "Attach certificate")

    {:ok, _lv, _html} =
      lv
      |> form("#accept-form", certificate: %{confirmed: true})
      |> render_submit()
      |> follow_redirect(ctx.conn)

    assert_received {:post, "/documents"}
    refute_received {:post, "/member-qualification-awards"}
    assert %{status: :accepted, d4h_award_id: 77} = Repo.reload!(ctx.certificate)

    assert %{d4h_document_id: 901, starts_at: ~U[2026-10-18 00:00:00Z]} =
             MemberQualificationAward.get_by(d4h_award_id: 77)
  end

  test "D4H has the award with a certificate: the team admin declines this one", ctx do
    stub_existing(ctx, [%{"id" => 5, "targetResource" => %{"id" => 77}}])
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/certificates/#{ctx.certificate.id}")
    assert has_element?(lv, "#certificate-existing", "with a certificate. Decline this one.")
    refute has_element?(lv, "#accept-form")
    assert has_element?(lv, "#decline-form")
  end
end
