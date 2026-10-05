defmodule App.Adapter.TwilioTest do
  use ExUnit.Case

  import App.AccountsFixtures

  alias App.Adapter.Twilio

  test "is off without the account settings" do
    refute Twilio.configured?()
  end

  test "posts the text to Twilio with the API key" do
    text_login_fixture()
    assert Twilio.configured?()

    Req.Test.stub(Twilio, fn conn ->
      assert conn.request_path == "/2010-04-01/Accounts/AC0/Messages.json"
      assert ["Basic " <> auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert Base.decode64!(auth) == "SK0:secret"

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert URI.decode_query(body) == %{
               "To" => "+16045551234",
               "From" => "+16045550100",
               "Body" => "Hi"
             }

      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SM1"})
    end)

    assert Twilio.send_sms("+16045551234", "Hi") == :ok
  end

  @tag :capture_log
  test "returns Twilio's status when it refuses" do
    text_login_fixture()

    Req.Test.stub(Twilio, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"code" => 21_211})
    end)

    assert Twilio.send_sms("+16045551234", "Hi") == {:error, 400}
  end
end
