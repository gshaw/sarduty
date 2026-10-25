defmodule App.Worker.SendLoginCodeWorkerTest do
  use App.DataCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Worker.SendLoginCodeWorker

  defp perform(args), do: SendLoginCodeWorker.perform(%Oban.Job{args: args})

  test "a refused text fails the job, so Oban tries again" do
    text_login_fixture()
    manager_fixture(team_fixture(), %{email: "pat@example.com", phone: "604-555-1234"})

    Req.Test.stub(App.Adapter.Twilio, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    assert perform(%{"phone" => "+16045551234"}) == {:error, 503}
  end

  test "a code that went, or no code for a stranger, completes the job" do
    manager_fixture(team_fixture(), %{email: "pat@example.com"})

    assert perform(%{"email" => "pat@example.com"}) == :ok
    assert_received {:email, _}
    assert perform(%{"email" => "stranger@example.com"}) == :ok
    refute_received {:email, _}
  end

  test "retries within a minute, while the person is waiting" do
    assert SendLoginCodeWorker.new(%{}).changes.max_attempts == 3
    assert Enum.map(1..2, &SendLoginCodeWorker.backoff(%Oban.Job{attempt: &1})) == [10, 20]
  end
end
