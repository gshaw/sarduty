defmodule Web.MeCertificateFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()

    qualification =
      qualification_fixture(team, %{title: "Standard First Aid", expires_months_default: 36})

    %{conn: log_in_user(conn, user), team: team, member: member, qualification: qualification}
  end

  test "a member sends a certificate, and it waits at the top of Qualifications", ctx do
    %{conn: conn, team: team, qualification: qualification} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me")
    assert has_element?(lv, "#certificate-add")

    {:ok, lv, _html} =
      live(conn, ~p"/teams/#{team}/me/certificates/new?#{[qualification: qualification.id]}")

    assert has_element?(
             lv,
             "#certificate_qualification_id-select option[selected]",
             "Standard First Aid"
           )

    assert has_element?(lv, "input[type=file][accept='image/*,application/pdf']")
    refute has_element?(lv, "input[type=file][capture]")

    # The combobox's select is hidden, so the test names its value.
    values = %{qualification_id: qualification.id, starts_on: "2026-10-18", ends_on: ""}
    lv |> form("#certificate-form", certificate: values) |> render_change()

    assert has_element?(lv, "#certificate_ends_on[value='2029-10-18']")
    assert has_element?(lv, "#certificate-form", "Filled in: Standard First Aid lasts 3 years.")

    # Cleared, it stays blank: it never expires.
    lv |> form("#certificate-form", certificate: %{values | ends_on: ""}) |> render_change()
    refute has_element?(lv, "#certificate_ends_on[value='2029-10-18']")
    lv |> form("#certificate-form", certificate: values) |> render_change()

    lv
    |> file_input("#certificate-form", :certificate, [
      %{name: "first-aid.pdf", content: "%PDF-1.7 certificate", type: "application/pdf"}
    ])
    |> render_upload("first-aid.pdf")

    {:ok, lv, _html} =
      lv
      |> form("#certificate-form", certificate: %{values | ends_on: "2029-10-18"})
      |> render_submit()
      |> follow_redirect(conn)

    [certificate] = Repo.all(Certificate)
    assert %{status: :waiting, starts_on: ~D[2026-10-18], ends_on: ~D[2029-10-18]} = certificate
    assert CertificateFile.bytes(certificate) == "%PDF-1.7 certificate"

    row = "#qualifications-list-certificate-#{certificate.id}"
    assert has_element?(lv, row, "Standard First Aid")
    assert has_element?(lv, row, "Waiting")
    assert has_element?(lv, row, "A team admin looks at it next.")
  end

  test "a member not sure of the qualification leaves it blank and writes a note", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/me/certificates/new")
    assert has_element?(lv, "#certificate_qualification_id[placeholder='Type to search']")

    lv
    |> file_input("#certificate-form", :certificate, [
      %{name: "wfa.pdf", content: "%PDF-1.7 certificate", type: "application/pdf"}
    ])
    |> render_upload("wfa.pdf")

    {:ok, lv, _html} =
      lv
      |> form("#certificate-form",
        certificate: %{starts_on: "2026-09-14", note: "  The 40-hour course.  "}
      )
      |> render_submit()
      |> follow_redirect(ctx.conn)

    [certificate] = Repo.all(Certificate)
    assert %{qualification_id: nil, note: "The 40-hour course."} = certificate

    row = "#qualifications-list-certificate-#{certificate.id}"
    assert has_element?(lv, row, "Certificate")
    assert has_element?(lv, row, "A team admin picks the qualification next.")
  end

  test "a certificate needs its file", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/me/certificates/new")

    html =
      lv
      |> form("#certificate-form",
        certificate: %{qualification_id: ctx.qualification.id, starts_on: "2026-10-18"}
      )
      |> render_submit()

    assert html =~ "Select a photo or a PDF of the certificate."
    assert Repo.all(Certificate) == []
  end

  test "a declined certificate shows why until the member deletes it", ctx do
    certificate =
      certificate_fixture(ctx.member, ctx.qualification, %{
        status: :declined,
        decline_reason: "This is for AST 2."
      })

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/me")
    row = "#qualifications-list-certificate-#{certificate.id}"
    assert has_element?(lv, row, "This is for AST 2.")
    assert has_element?(lv, row, "Declined")

    lv |> element("#certificate-delete-#{certificate.id}") |> render_click()
    refute has_element?(lv, row)
    assert Repo.all(Certificate) == []
  end

  test "the form is gone once the award is in D4H, and with certificates off", ctx do
    certificate = certificate_fixture(ctx.member, ctx.qualification, %{d4h_award_id: 300})

    assert_raise Web.Status.NotFound, fn ->
      live(ctx.conn, ~p"/teams/#{ctx.team}/me/certificates/#{certificate.id}/edit")
    end

    ctx.team |> Ecto.Changeset.change(certificates_enabled: false) |> Repo.update!()

    assert_raise Web.Status.NotFound, fn ->
      live(ctx.conn, ~p"/teams/#{ctx.team}/me/certificates/new")
    end

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/me")
    refute has_element?(lv, "#certificate-add")
  end

  test "the member's own file, and only theirs", ctx do
    certificate = certificate_fixture(ctx.member, ctx.qualification)
    conn = get(ctx.conn, ~p"/teams/#{ctx.team}/me/certificates/#{certificate.id}/file")
    assert conn.resp_body == "%PDF-1.7\n"
    assert get_resp_header(conn, "content-security-policy") == ["sandbox"]
    # It changes and goes, so no browser keeps it.
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]

    other = certificate_fixture(member_fixture(ctx.team), ctx.qualification)

    assert_error_sent 404, fn ->
      get(ctx.conn, ~p"/teams/#{ctx.team}/me/certificates/#{other.id}/file")
    end
  end
end
