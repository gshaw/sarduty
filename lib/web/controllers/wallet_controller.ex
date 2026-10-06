defmodule Web.WalletController do
  @moduledoc """
  Apple's pass web service, which Wallet calls under the pass's `webServiceURL`:
  register and unregister a phone, list changed passes, and fetch a pass. Calls about
  one pass prove themselves with `Authorization: ApplePass <authenticationToken>`.
  """
  use Web, :controller

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.BuildApplePass
  alias App.RateLimit
  alias Web.VerifyLimit

  require Logger

  def register(conn, %{"device" => device, "pass_type" => pass_type, "serial" => serial} = params) do
    with {:ok, card} <- authorize(conn, pass_type, serial),
         token when is_binary(token) and token != "" <- params["pushToken"] do
      case PassRegistration.register!(card, device, token) do
        :created -> send_resp(conn, 201, "")
        :existing -> send_resp(conn, 200, "")
      end
    else
      :unauthorized -> send_resp(conn, 401, "")
      _ -> send_resp(conn, 400, "")
    end
  end

  def unregister(conn, %{"device" => device, "pass_type" => pass_type, "serial" => serial}) do
    case authorize(conn, pass_type, serial) do
      {:ok, card} ->
        PassRegistration.unregister!(card, device)
        send_resp(conn, 200, "")

      :unauthorized ->
        send_resp(conn, 401, "")
    end
  end

  # The device library id is the secret here: only the phone knows it.
  def serial_numbers(conn, %{"device" => device, "pass_type" => pass_type} = params) do
    since = parse_tag(params["passesUpdatedSince"])

    cards =
      if pass_type == pass_type_id(),
        do: PassRegistration.cards_for_device(device, since),
        else: []

    case cards do
      [] ->
        send_resp(conn, 204, "")

      cards ->
        last = cards |> Enum.map(& &1.pass_updated_at) |> Enum.max(DateTime)

        json(conn, %{
          serialNumbers: cards |> Enum.map(&MemberCard.serial_number/1) |> Enum.uniq(),
          lastUpdated: last |> DateTime.to_unix(:microsecond) |> Integer.to_string()
        })
    end
  end

  def pass(conn, %{"pass_type" => pass_type, "serial" => serial}) do
    now = DateTime.utc_now()

    with {:ok, card} <- authorize(conn, pass_type, serial),
         {:ok, pkpass} <- BuildApplePass.call(card, now) do
      MemberCard.record_pass_fetched!(card, now)

      conn
      |> put_resp_content_type("application/vnd.apple.pkpass", nil)
      |> put_resp_header("last-modified", last_modified(card))
      |> send_resp(200, pkpass)
    else
      :unauthorized -> send_resp(conn, 401, "")
      _ -> send_resp(conn, 404, "")
    end
  end

  @log_messages 10
  @log_length 500
  @log_ip_limit 50

  # Wallet posts its own error messages here. They help when a pass won't update. Apple
  # sends no auth, so anyone can post: keep 10 messages a post, 500 characters each, and
  # 50 messages an hour from one IP (#176).
  def log(conn, params) do
    key = "wallet_log:#{conn |> VerifyLimit.client_ip() |> RateLimit.ip_key()}"

    for message <- params["logs"] |> List.wrap() |> Enum.take(@log_messages),
        is_binary(message),
        RateLimit.inc(key, :timer.hours(1)) <= @log_ip_limit do
      Logger.warning("Wallet: #{String.slice(message, 0, @log_length)}")
    end

    send_resp(conn, 200, "")
  end

  defp authorize(conn, pass_type, serial) do
    with true <- pass_type == pass_type_id(),
         ["ApplePass " <> token] <- get_req_header(conn, "authorization"),
         %MemberCard{} = card <- MemberCard.find_by_serial_number_and_token(serial, token) do
      {:ok, card}
    else
      _ -> :unauthorized
    end
  end

  defp pass_type_id, do: Application.get_env(:sarduty, :apple_pass, [])[:pass_type_id]

  defp parse_tag(nil), do: nil

  defp parse_tag(tag) do
    case Integer.parse(tag) do
      {microseconds, ""} -> DateTime.from_unix!(microseconds, :microsecond)
      _ -> nil
    end
  end

  defp last_modified(card) do
    card.pass_updated_at
    |> Kernel.||(card.inserted_at)
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end
end
