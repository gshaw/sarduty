defmodule App.Operation.PushPassUpdates do
  alias App.Adapter.APNs
  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildCardQualifications
  alias App.Worker.UpdateCardWorker

  require Logger

  @doc """
  After a D4H refresh: rebuilds the pass of each of the team's cards on a phone, and
  returns the ones where anything a member would see changed, for UpdateCardWorker to
  push. Records each new fingerprint, so a card is pushed once per change.
  """
  def changed_cards(%Team{} = team, now) do
    if BuildApplePass.configured?(),
      do: team |> MemberCard.get_all_registered() |> Enum.filter(&changed?(&1, now)),
      else: []
  end

  @doc """
  While a replacement's page waits on Apple Wallet (#952): its phones still hold the
  cancelled card until one fetches the replacement, and Wallet doesn't register it
  again. Marks the pass updated and queues a push, so a phone that now holds the
  replacement fetches it with its own token, which `count_holding/1` then counts. A
  phone still holding the cancelled card fetches that again, unchanged and silent. Does
  nothing for a card a phone already holds, or a serial no phone has.
  """
  def nudge_replacement(%MemberCard{} = card, now) do
    if BuildApplePass.configured?() and PassRegistration.count_holding(card) == 0 and
         PassRegistration.get_all_for_serial(card) != [] do
      card |> MemberCard.touch_pass_updated!(now) |> UpdateCardWorker.enqueue()
    end

    :ok
  end

  @doc "Pushes to every phone that holds the card's pass. For UpdateCardWorker only."
  def push_card(%MemberCard{} = card) do
    if BuildApplePass.configured?(),
      do: card |> PassRegistration.get_all_for_serial() |> Enum.each(&push(card, &1))

    :ok
  rescue
    # A push is a nudge; the phone still gets the change on its next check. Log it
    # rather than fail the job, which also sends the Google pass.
    error ->
      Logger.warning("pass push failed: #{Exception.message(error)}")
      :ok
  end

  defp push(card, registration) do
    case APNs.push_pass_update(registration.push_token, config()) do
      :ok -> :ok
      {:error, :unregistered} -> drop(card, registration)
      {:error, _status} -> :error
    end
  end

  defp changed?(card, now) do
    status = MemberCard.status(card, now)
    card = MemberCard.record_expires_at!(card, status)
    qualifications = BuildCardQualifications.call(card.member.team, card.member, now)

    fingerprint =
      card
      |> BuildApplePass.pass_json(status, qualifications, config())
      |> BuildApplePass.fingerprint()

    if fingerprint == card.pass_fingerprint do
      false
    else
      MemberCard.record_pass!(card, fingerprint, now)
      true
    end
  end

  # A phone that dropped the pass without telling us. Its card's pages count it, so they
  # hear of it as they do of an unregister.
  defp drop(card, registration) do
    PassRegistration.delete!(registration)
    MemberCard.broadcast_wallet_changed(card.member_id)
  end

  defp config, do: :sarduty |> Application.get_env(:apple_pass) |> Map.new()
end
