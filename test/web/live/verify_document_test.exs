defmodule Web.VerifyDocumentTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.PublishedPDF
  alias App.Repo

  # A published PDF's verify code opens the verify site's root (#970), beside the ID
  # card check: matched by host, with a client IP of its own per test.
  setup %{conn: conn} do
    team =
      %{name: "NSR", legal_name: "North Shore Rescue"}
      |> team_fixture()
      |> Ecto.Changeset.change(authorized_by_name: "Pat Lee", authorized_by_phone: "604-555-0100")
      |> Repo.update!()

    member = member_fixture(team, %{name: "Mercer, Nadia"})
    conn = conn |> Map.put(:host, Web.VerifyHost.host()) |> with_ip(unique_ip())
    %{conn: conn, team: team, member: member}
  end

  defp unique_ip, do: "10.2.#{System.unique_integer([:positive])}"
  defp with_ip(conn, ip), do: put_req_header(conn, "fly-client-ip", ip)

  defp letter(member, attrs \\ %{}) do
    attrs =
      Map.merge(%{year: 2025, primary_minutes: 212 * 60 + 30, secondary_minutes: 18 * 60}, attrs)

    tax_credit_letter_fixture(member, attrs)
  end

  defp path(%{pdf: pdf}), do: ~p"/#{PublishedPDF.format_code(pdf.code)}"

  test "a typed ID shows what the document's verify page shows", %{conn: conn, member: member} do
    letter = letter(member)
    {:ok, lv, _html} = live(conn, ~p"/")

    typed = letter.pdf.code |> String.downcase()
    lv |> form("#check-form", check: %{code: typed}) |> render_submit()

    assert_patch(lv, path(letter))
    assert has_element?(lv, "#result-current", "Published by North Shore Rescue")
    assert has_element?(lv, "#result-team", "North Shore Rescue")
    assert has_element?(lv, "#result-shows", "Mercer, Nadia")
    assert has_element?(lv, "#result-shows", "212h 30m")
    assert has_element?(lv, "#result-shows", "230h 30m")
    assert has_element?(lv, "#result-contact", "604-555-0100")
  end

  test "the verify code's link opens straight to the result", %{conn: conn, member: member} do
    letter = letter(member)
    {:ok, lv, _html} = live(conn, path(letter))
    assert has_element?(lv, "#result-current")

    # Scanned from the start page: the QR code holds the link in capitals.
    {:ok, lv, _html} = live(conn, ~p"/")
    link = letter.pdf.code |> PublishedPDF.verify_link() |> String.upcase()
    lv |> render_hook("scanned", %{"code" => link})
    assert_patch(lv, path(letter))
  end

  test "a letter's code from before #970 is not found, nor its old link (#970)",
       %{conn: conn, member: member} do
    letter(member, %{code: "SRVTC-K7Q4M2XA"})

    {:ok, lv, _html} = live(conn, "/SRVTC-K7Q4M2XA")
    assert has_element?(lv, "#result-not-found")

    # Its QR code's link, scanned from the start page.
    {:ok, lv, _html} = live(conn, ~p"/")

    lv
    |> render_hook("scanned", %{
      "code" => "https://#{Web.VerifyHost.host()}/letters/SRVTC-K7Q4M2XA"
    })

    assert has_element?(lv, "#result-not-found")
  end

  test "an unknown ID is not found", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/ZZZZZ-ZZZZZ-ZZZZZ")
    assert has_element?(lv, "#result-not-found", "No document has this code")
  end

  test "a replaced one says so and shows nothing from the PDF", %{conn: conn, member: member} do
    old = letter(member)

    {:ok, new} =
      PublishedPDF.publish(
        %{
          team_id: old.pdf.team_id,
          name: old.pdf.name,
          subject: old.pdf.subject,
          code: PublishedPDF.generate_code()
        },
        %{attachment: %{content: "%PDF new", title: "New", filename: "new.pdf"}},
        old.pdf.id
      )

    {:ok, lv, html} = live(conn, path(old))
    assert has_element?(lv, "#result-replaced", "Ask North Shore Rescue for the current one.")
    assert has_element?(lv, "#result-name", "Tax credit letter")
    refute html =~ "Mercer"

    {:ok, lv, _html} = live(conn, path(%{pdf: new}))
    assert has_element?(lv, "#result-current")
  end

  test "a withdrawn one says who withdrew it, and shows nothing from the PDF",
       %{conn: conn, member: member} do
    letter = letter(member)

    letter.pdf
    |> Ecto.Changeset.change(withdrawn_at: ~U[2027-03-03 18:00:00.000000Z])
    |> Repo.update!()

    {:ok, lv, html} = live(conn, path(letter))

    assert has_element?(
             lv,
             "#result-withdrawn",
             "Withdrawn by North Shore Rescue on March 3, 2027."
           )

    refute html =~ "Mercer"
  end

  test "misses share the ID card check's limit", %{conn: conn, member: member} do
    letter = letter(member)

    for _ <- 1..20 do
      {:ok, _lv, _html} = live(conn, ~p"/ZZZZZ-ZZZZZ-ZZZZZ")
    end

    {:ok, lv, _html} = live(conn, path(letter))
    assert has_element?(lv, "#result-limited", "Wait a few minutes")
    refute has_element?(lv, "#result-current")
  end
end
