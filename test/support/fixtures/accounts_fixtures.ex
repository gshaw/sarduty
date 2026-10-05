defmodule App.AccountsFixtures do
  @moduledoc """
  Test helpers for users. A user reaches a team only through a manager member with the
  same email; App.DataFixtures.user_with_team_fixture/1 makes both.
  """

  alias App.Accounts.User
  alias App.Repo

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def user_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %{email: attrs[:email] || unique_user_email()}
    |> User.new_changeset()
    |> Ecto.Changeset.change(Map.drop(attrs, [:email]))
    |> Repo.insert!()
  end

  @doc "Sends a login code to the email through the test mailer and returns it."
  def login_code_fixture(email) do
    :ok = App.Accounts.deliver_login_code(email)

    receive do
      {:email, %{subject: "Your SAR Duty login code: " <> code}} -> code
    after
      0 -> raise "no login code was sent to #{email}"
    end
  end

  @doc """
  Turns text login on for this test, with Twilio stubbed: each text arrives in the test
  process as `{:text, to, body}`.
  """
  def text_login_fixture do
    original = Application.get_env(:sarduty, App.Adapter.Twilio)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:sarduty, App.Adapter.Twilio, original) end)

    Application.put_env(
      :sarduty,
      App.Adapter.Twilio,
      Keyword.merge(original,
        account_sid: "AC0",
        api_key_sid: "SK0",
        api_key_secret: "secret",
        from_number: "+16045550100"
      )
    )

    test = self()

    Req.Test.stub(App.Adapter.Twilio, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)
      send(test, {:text, params["To"], params["Body"]})
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SM0"})
    end)

    :ok
  end

  @doc "Texts a login code to the E.164 number through the Twilio stub and returns it."
  def text_code_fixture(phone) do
    :ok = App.Accounts.deliver_login_text(phone)

    receive do
      {:text, ^phone, "Your SAR Duty login code: " <> <<code::binary-6, _rest::binary>>} -> code
    after
      0 -> raise "no login code was texted to #{phone}"
    end
  end
end
