defmodule App.Adapter.CloudflareEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.Email

  alias App.Adapter.CloudflareEmail

  @config [
    account_id: "account-1",
    api_token: "token-1",
    req_options: [plug: {Req.Test, App.Adapter.CloudflareEmail}, retry: false]
  ]

  defp letter_email do
    new()
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> to("member@example.com")
    |> subject("2025 Tax Credit Letter")
    |> text_body("Attached is the letter.")
    |> attachment(
      Swoosh.Attachment.new({:data, "%PDF-1.4"},
        filename: "letter.pdf",
        content_type: "application/pdf"
      )
    )
  end

  test "posts the email to the account's send endpoint" do
    Req.Test.stub(App.Adapter.CloudflareEmail, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/client/v4/accounts/account-1/email/sending/send"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token-1"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "from" => %{"address" => "noreply@sarduty.com", "name" => "SAR Duty"},
               "to" => ["member@example.com"],
               "subject" => "2025 Tax Credit Letter",
               "text" => "Attached is the letter.",
               "attachments" => [
                 %{
                   "content" => Base.encode64("%PDF-1.4"),
                   "filename" => "letter.pdf",
                   "type" => "application/pdf",
                   "disposition" => "attachment"
                 }
               ]
             }

      Req.Test.json(conn, %{
        "success" => true,
        "errors" => [],
        "messages" => [],
        "result" => %{
          "message_id" => "<abc@sarduty.com>",
          "delivered" => ["member@example.com"],
          "queued" => [],
          "permanent_bounces" => [],
          "suppressed_recipients" => []
        }
      })
    end)

    assert CloudflareEmail.deliver(letter_email(), @config) ==
             {:ok,
              %{
                id: "<abc@sarduty.com>",
                delivered: ["member@example.com"],
                queued: [],
                permanent_bounces: []
              }}
  end

  test "returns the status and body when Cloudflare refuses the email" do
    error = %{
      "success" => false,
      "errors" => [%{"code" => 10_203, "message" => "email.sending.error.email.sending_disabled"}],
      "messages" => [],
      "result" => nil
    }

    Req.Test.stub(App.Adapter.CloudflareEmail, fn conn ->
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(error)
    end)

    assert CloudflareEmail.deliver(letter_email(), @config) == {:error, {403, error}}
  end
end
