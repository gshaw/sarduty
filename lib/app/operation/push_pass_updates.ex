defmodule App.Operation.PushPassUpdates do
  alias App.Adapter.APNs
  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Model.Team
  alias App.Operation.BuildApplePass
  alias App.Operation.BuildCardQualifications

  require Logger

  @doc """
  After a D4H refresh: for each of the team's cards on a phone, rebuilds the pass and
  pushes to its phones if anything a member would see has changed.
  """
  def call(%Team{} = team, now) do
    if BuildApplePass.configured?() do
      for card <- MemberCard.get_all_registered(team), changed?(card, now), do: push(card)
    end

    :ok
  end

  @doc "Pushes to every phone that holds these cards' passes, as for a cancelled card."
  def push_cards(cards) do
    if BuildApplePass.configured?(), do: Enum.each(cards, &push/1)
    :ok
  end

  # Records the new fingerprint as it goes, so a card is pushed once per change.
  defp changed?(card, now) do
    qualifications = BuildCardQualifications.call(card.member.team, card.member, now)

    fingerprint =
      card
      |> BuildApplePass.pass_json(qualifications, config(), now)
      |> BuildApplePass.fingerprint()

    if fingerprint == card.pass_fingerprint do
      false
    else
      MemberCard.record_pass!(card, fingerprint, now)
      true
    end
  end

  defp push(card) do
    for registration <- PassRegistration.get_all_for_serial(card) do
      case APNs.push_pass_update(registration.push_token, config()) do
        :ok -> :ok
        {:error, :unregistered} -> PassRegistration.delete!(registration)
        {:error, _status} -> :error
      end
    end
  rescue
    # A push is a nudge; the phone still gets the change on its next check. Log it
    # rather than fail the refresh or the cancel that caused it.
    error -> Logger.warning("pass push failed: #{Exception.message(error)}")
  end

  defp config, do: :sarduty |> Application.get_env(:apple_pass) |> Map.new()
end
