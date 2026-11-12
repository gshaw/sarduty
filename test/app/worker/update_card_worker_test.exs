defmodule App.Worker.UpdateCardWorkerTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures

  alias App.Operation.IssueMemberCard
  alias App.Worker.UpdateCardWorker

  setup do
    App.GoogleWalletCredentials.configure()
    team = team_fixture()
    member = member_fixture(team)
    card = member_card_fixture(member, %{google_pass_fingerprint: "old"})
    %{team: team, member: member, card: card}
  end

  defp perform(card),
    do: UpdateCardWorker.perform(%Oban.Job{args: %{"member_card_id" => card.id}})

  test "many cards go out 6 seconds apart, the first now", %{team: team} do
    cards = for _ <- 1..3, do: team |> member_fixture() |> member_card_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      UpdateCardWorker.enqueue_all(cards)
      jobs = all_enqueued(worker: UpdateCardWorker)
      first = jobs |> Enum.map(& &1.scheduled_at) |> Enum.min(DateTime)
      gaps = jobs |> Enum.map(&DateTime.diff(&1.scheduled_at, first)) |> Enum.sort()
      assert gaps == [0, 6, 12]
    end)
  end

  test "a second batch lines up behind the first; one card goes now", %{team: team} do
    cards = for _ <- 1..4, do: team |> member_fixture() |> member_card_fixture()
    {first, second} = Enum.split(cards, 2)

    Oban.Testing.with_testing_mode(:manual, fn ->
      UpdateCardWorker.enqueue_all(first)
      UpdateCardWorker.enqueue_all(second)
      jobs = all_enqueued(worker: UpdateCardWorker)
      start = jobs |> Enum.map(& &1.scheduled_at) |> Enum.min(DateTime)
      gaps = jobs |> Enum.map(&DateTime.diff(&1.scheduled_at, start)) |> Enum.sort()
      assert gaps == [0, 6, 12, 18]

      card = team |> member_fixture() |> member_card_fixture()
      UpdateCardWorker.enqueue(card)

      [single] = all_enqueued(worker: UpdateCardWorker, args: %{member_card_id: card.id})
      assert DateTime.diff(single.scheduled_at, start) < 2
    end)
  end

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

    # Its job runs inline with the replacement, and fails.
    {:ok, _card} = IssueMemberCard.call(ctx.team, ctx.member, DateTime.utc_now())
    assert_received :object_refused
    assert Repo.reload!(ctx.card).google_pass_fingerprint == "old"

    App.GoogleWalletCredentials.stub(self())
    assert perform(ctx.card) == :ok
    assert_received {:google, "PUT", _path, %{"state" => "EXPIRED"}}
    refute Repo.reload!(ctx.card).google_pass_fingerprint == "old"
  end

  test "a live card's changed pass is sent", ctx do
    App.GoogleWalletCredentials.stub(self())
    assert perform(ctx.card) == :ok
    assert_received {:google, "PUT", _path, %{"state" => "ACTIVE"}}
  end

  test "a card that's gone is cancelled", ctx do
    assert {:cancel, _reason} =
             UpdateCardWorker.perform(%Oban.Job{args: %{"member_card_id" => ctx.card.id + 1000}})
  end
end
