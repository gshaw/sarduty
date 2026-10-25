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

  @doc """
  Sends these cards' passes, as for a cancelled card, if Google has them. `:ok`, or
  `{:error, reason}` when Google refused one, for the job to try again.
  """
  def update_cards(cards, now) do
    if BuildGooglePass.configured?() do
      cards
      |> Enum.reject(&is_nil(&1.google_pass_fingerprint))
      |> Repo.preload(member: [team: :organization])
      |> send_changed(now)
    else
      :ok
    end
  end

  defp send_changed(cards, now) do
    config = BuildGooglePass.config()

    changed =
      for card <- cards,
          object = object(card, config, now),
          BuildGooglePass.fingerprint(object) != card.google_pass_fingerprint,
          do: {card, object}

    if changed == [], do: :ok, else: send_objects(changed, config, now)
  rescue
    # A refresh's failed update goes after the next refresh, since the fingerprint didn't
    # change, and a cancelled card's job tries again. Log it rather than fail either.
    error ->
      Logger.warning("Google pass update failed: #{Exception.message(error)}")
      {:error, Exception.message(error)}
  end

  defp send_objects(changed, config, now) do
    {:ok, token} = GoogleWallet.access_token(config.credentials, now)
    # The class is otherwise sent only when a pass is added, so a change to its front
    # row would never reach the passes already out there.
    :ok = GoogleWallet.upsert(token, "genericClass", BuildGooglePass.pass_class(config))

    results =
      for {card, object} <- changed do
        with :ok <- GoogleWallet.upsert(token, "genericObject", object) do
          MemberCard.record_google_pass!(card, BuildGooglePass.fingerprint(object))
          :ok
        end
      end

    Enum.find(results, :ok, &(&1 != :ok))
  end

  defp object(card, config, now) do
    qualifications = BuildCardQualifications.call(card.member.team, card.member, now)
    BuildGooglePass.pass_object(card, qualifications, config, now)
  end
end
