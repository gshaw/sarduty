defmodule App.MailerTest do
  use App.DataCase, async: true

  import App.DataFixtures
  # Not from/2, which Ecto.Query's import already names.
  import Swoosh.Email, only: [new: 0, subject: 2, text_body: 2, cc: 2]

  alias App.Mailer
  alias App.Model.Member

  # Sends through the Cloudflare adapter, with Cloudflare stubbed by refuse_as/1.
  @cloudflare [
    adapter: App.Adapter.CloudflareEmail,
    account_id: "account-1",
    api_token: "token-1",
    req_options: [plug: {Req.Test, App.Adapter.CloudflareEmail}, retry: false]
  ]

  # Cloudflare refuses the send for a suppressed recipient, blocked for `reason` for good.
  defp refuse_as(reason) do
    Req.Test.stub(App.Adapter.CloudflareEmail, fn
      %{method: "POST"} = conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"success" => false, "errors" => [%{"code" => 10_205}]})

      %{method: "GET"} = conn ->
        Req.Test.json(conn, %{"result" => [%{"reason" => reason, "expires_at" => nil}]})
    end)
  end

  defp email_to(member, team) do
    new()
    |> Mailer.to_member(member)
    |> Swoosh.Email.from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Hello")
    |> text_body("Hello")
    |> Mailer.for_team(team)
  end

  test "to_member/2 addresses the member by name" do
    member = member_fixture(team_fixture(), %{name: "Pat Lee", email: "pat@example.com"})

    assert email_to(member, team_fixture()).to == [{"Pat Lee", "pat@example.com"}]
  end

  describe "email problems" do
    test "a refusal saves the problem on every member with that address, on every team" do
      team = team_fixture()
      member = member_fixture(team, %{email: "pat@example.com"})
      elsewhere = member_fixture(team_fixture(), %{email: "Pat@Example.com"})
      other = member_fixture(team, %{email: "sam@example.com"})
      refuse_as("hard_bounce")

      assert member |> email_to(team) |> Mailer.deliver(@cloudflare) ==
               {:error, {:email_problem, :no_such_address}}

      assert Repo.reload!(member).email_problem == :no_such_address
      assert Repo.reload!(elsewhere).email_problem == :no_such_address
      assert Repo.reload!(other).email_problem == nil
    end

    test "a refused email to several people saves nothing, since it doesn't say whose" do
      team = team_fixture()
      member = member_fixture(team, %{email: "pat@example.com"})
      refuse_as("hard_bounce")
      email = member |> email_to(team) |> cc("sam@example.com")

      assert Mailer.deliver(email, @cloudflare) == {:error, {:email_problem, :blocked}}
      assert Repo.reload!(member).email_problem == nil
    end

    test "an email to the member that goes out clears their problem everywhere" do
      team = team_fixture()
      member = member_fixture(team, %{email: "pat@example.com"})
      elsewhere = member_fixture(team_fixture(), %{email: "pat@example.com"})
      Member.record_email_problem("pat@example.com", :spam_report)

      assert {:ok, _sent} = member |> Repo.reload!() |> email_to(team) |> Mailer.deliver()

      assert Repo.reload!(member).email_problem == nil
      assert Repo.reload!(elsewhere).email_problem == nil
    end
  end
end
