defmodule App.Operation.RecordGoogleWalletEvent do
  @moduledoc """
  Google Wallet tells SAR Duty when a member saves or deletes their card's pass (#389),
  through the class's `callbackOptions`. A save marks the card in Wallet, which takes it
  off the member's For you to do; a delete clears the mark. Google retries until it gets
  a 200, and may send a message twice, so both are safe to repeat.
  """

  alias App.Adapter.GoogleWallet
  alias App.Model.MemberCard
  alias App.Operation.BuildGooglePass
  alias App.Repo

  @doc "`:ok` for a message SAR Duty took or had no card for, or `{:error, reason}`."
  def call(body, now) do
    if BuildGooglePass.configured?() do
      config = BuildGooglePass.config()

      with {:ok, root_keys} <- GoogleWallet.fetch_callback_keys(now),
           {:ok, message} <- GoogleWallet.Callback.verify(body, root_keys, config.issuer_id, now) do
        record(message, config, now)
      end
    else
      {:error, :not_configured}
    end
  end

  # Another host's class, such as dev's on the shared issuer, or a card that's gone.
  defp record(%{class_id: class_id, object_id: object_id, event: event}, config, now) do
    with true <- class_id == BuildGooglePass.pass_class(config).id,
         %MemberCard{} = card <- find_card(object_id, config) do
      case event do
        :save -> MemberCard.mark_in_wallet!(card, now)
        :delete -> MemberCard.mark_out_of_wallet!(card)
      end
    end

    :ok
  end

  defp find_card(object_id, config) do
    prefix = BuildGooglePass.object_id(%MemberCard{id: ""}, config)

    with ^prefix <> id <- object_id,
         {id, ""} <- Integer.parse(id) do
      Repo.get(MemberCard, id)
    else
      _other -> nil
    end
  end
end
