defmodule App.Operation.UpdateGooglePasses do
  alias App.Adapter.GoogleWallet
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Operation.BuildCardQualifications
  alias App.Operation.BuildGooglePass
  alias App.Repo

  require Logger

  @doc """
  After a D4H refresh: sends Google each of the team's passes that changed. Google
  updates every saved copy.
  """
  def call(%Team{} = team, now) do
    if BuildGooglePass.configured?(),
      do: team |> MemberCard.get_all_on_google() |> send_changed(now)

    :ok
  end

  @doc "Sends these cards' passes, as for a cancelled card, if Google has them."
  def update_cards(cards, now) do
    if BuildGooglePass.configured?() do
      cards
      |> Enum.reject(&is_nil(&1.google_pass_fingerprint))
      |> Repo.preload(member: :team)
      |> send_changed(now)
    end

    :ok
  end

  defp send_changed(cards, now) do
    config = BuildGooglePass.config()

    changed =
      for card <- cards,
          object = object(card, config, now),
          BuildGooglePass.fingerprint(object) != card.google_pass_fingerprint,
          do: {card, object}

    if changed != [] do
      {:ok, token} = GoogleWallet.access_token(config.credentials, now)
      # The class is otherwise sent only when a pass is added, so a change to its front
      # row would never reach the passes already out there.
      :ok = GoogleWallet.upsert(token, "genericClass", BuildGooglePass.pass_class(config))

      for {card, object} <- changed,
          GoogleWallet.upsert(token, "genericObject", object) == :ok,
          do: MemberCard.record_google_pass!(card, BuildGooglePass.fingerprint(object))
    end
  rescue
    # An update that fails is sent after the next refresh, since the fingerprint didn't
    # change. Log it rather than fail the refresh or the cancel that caused it.
    error -> Logger.warning("Google pass update failed: #{Exception.message(error)}")
  end

  defp object(card, config, now) do
    qualifications = BuildCardQualifications.call(card.member.team, card.member, now)
    BuildGooglePass.pass_object(card, qualifications, config, now)
  end
end
