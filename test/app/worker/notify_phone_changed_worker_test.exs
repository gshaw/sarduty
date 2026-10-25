defmodule App.Worker.NotifyPhoneChangedWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Worker.NotifyPhoneChangedWorker

  defp perform(member),
    do: NotifyPhoneChangedWorker.perform(%Oban.Job{args: %{"member_id" => member.id}})

  test "emails the member the number they have now" do
    team = team_fixture(%{name: "Ridge SAR"})
    member = member_fixture(team, %{email: "pat@example.com", phone: "604-555-0123"})

    assert perform(member) == :ok
    assert_received {:email, %{to: [{"", "pat@example.com"}], text_body: body}}
    assert body =~ "Your mobile number on Ridge SAR is now 604-555-0123."
  end

  test "a refusal fails the job, so it's tried again" do
    member = member_fixture(team_fixture(), %{email: "pat@example.com"})
    refusing_mailer_fixture()

    assert {:error, _reason} = perform(member)
  end

  test "a member with no email gets nothing" do
    member = member_fixture(team_fixture(), %{email: nil})

    assert {:cancel, _reason} = perform(member)
    refute_received {:email, _}
  end
end
