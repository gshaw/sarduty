defmodule Web.GoogleWalletController do
  use Web, :controller

  alias App.Operation.RecordGoogleWalletEvent

  require Logger

  # Google Wallet's save and delete callbacks (#389): a signed JSON body, no session. A
  # 200 tells Google to stop retrying, so a bad signature gets a 400 and is logged.
  def callback(conn, params) do
    case RecordGoogleWalletEvent.call(params, DateTime.utc_now()) do
      :ok ->
        send_resp(conn, 200, "")

      {:error, reason} ->
        Logger.warning("Google Wallet callback refused: #{inspect(reason)}")
        send_resp(conn, 400, "")
    end
  end
end
