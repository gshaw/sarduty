defmodule Web.Admin.IntegrationPassController do
  use Web, :controller

  alias App.Operation.TestIntegration

  # Adminland › Integrations' Wallet tests (#789). A test that works sends the pass or
  # goes to Google; one that fails goes back to the page with its reason in a toast.
  def apple_pass(conn, _params) do
    case TestIntegration.call("apple", %{}, conn.assigns.current_user) do
      {:ok, _outcome, _message, pkpass} ->
        send_download(conn, {:binary, pkpass},
          filename: "sarduty-test-pass.pkpass",
          content_type: "application/vnd.apple.pkpass"
        )

      {:error, _outcome, message} ->
        conn |> put_flash(:error, message) |> redirect(to: ~p"/admin/integrations")
    end
  end

  # Step 0 of #918: the test letter Typst made, locked, to open and look at.
  def typst_letter(conn, _params) do
    case TestIntegration.call("typst", %{}, conn.assigns.current_user) do
      {:ok, _outcome, _message, pdf} ->
        send_download(conn, {:binary, pdf},
          filename: "sarduty-typst-test.pdf",
          content_type: "application/pdf"
        )

      {:error, _outcome, message} ->
        conn |> put_flash(:error, message) |> redirect(to: ~p"/admin/integrations")
    end
  end

  def google_pass(conn, _params) do
    case TestIntegration.call("google", %{}, conn.assigns.current_user) do
      {:ok, _outcome, _message, url} ->
        redirect(conn, external: url)

      {:error, _outcome, message} ->
        conn |> put_flash(:error, message) |> redirect(to: ~p"/admin/integrations")
    end
  end
end
