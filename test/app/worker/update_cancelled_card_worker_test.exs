defmodule App.Worker.UpdateCancelledCardWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Operation.RevokeMemberCard
  alias App.Worker.UpdateCancelledCardWorker

  setup do
    App.GoogleWalletCredentials.configure()
    team = team_fixture()
    member = member_fixture(team)
    card = member_card_fixture(member, %{google_pass_fingerprint: "old"})
    %{team: team, member: member, card: card}
  end

  defp perform(card),
    do: UpdateCancelledCardWorker.perform(%Oban.Job{args: %{"member_card_id" => card.id}})

  test "a Google refusal fails the job, so the cancelled pass is sent again", ctx do
    test = self()

    Req.Test.stub(App.Adapter.GoogleWallet, fn conn ->
      cond do
        conn.host == "oauth2.googleapis.com" ->
          Req.Test.json(conn, %{"access_token" => "access-token"})

        String.contains?(conn.request_path, "genericObject") ->
          send(test, :object_refused)
          conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})

        true ->
          Req.Test.json(conn, %{})
      end
    end)

    # Its job runs inline with the cancel, and fails.
    RevokeMemberCard.call(ctx.team, ctx.member, DateTime.utc_now())
    assert_received :object_refused
    assert Repo.reload!(ctx.card).google_pass_fingerprint == "old"

    App.GoogleWalletCredentials.stub(self())
    assert perform(ctx.card) == :ok
    assert_received {:google, "PUT", _path, %{"state" => "EXPIRED"}}
    refute Repo.reload!(ctx.card).google_pass_fingerprint == "old"
  end

  test "a live card is left alone", ctx do
    App.GoogleWalletCredentials.stub(self())
    assert {:cancel, _reason} = perform(ctx.card)
    refute_received {:google, _, _, _}
  end
end
