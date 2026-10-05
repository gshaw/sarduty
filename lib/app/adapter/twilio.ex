defmodule App.Adapter.Twilio do
  @moduledoc """
  Twilio, for texting login codes. Optional: with any of the four TWILIO_* settings
  missing, SAR Duty offers no text login. Dev logs a text instead of sending it unless
  DEV_SEND_SMS is set, because a dev database can hold real members' numbers.
  """

  require Logger

  @host "https://api.twilio.com"
  @settings [:account_sid, :api_key_sid, :api_key_secret, :from_number]

  @doc "Whether all four settings are present, so texts can go out."
  def configured? do
    config = config()
    Enum.all?(@settings, &(is_binary(config[&1]) and config[&1] != ""))
  end

  @doc "Whether a text really goes to Twilio. False in dev unless DEV_SEND_SMS is set."
  def delivers?, do: config()[:deliver] == true

  @doc "Texts `body` to an E.164 number. `:ok`, or `{:error, status}`."
  def send_sms(to, body) do
    if delivers?() do
      post_message(config(), to, body)
    else
      Logger.info("Text to #{to}, not sent (DEV_SEND_SMS is off):\n#{body}")
      :ok
    end
  end

  defp post_message(config, to, body) do
    response =
      [
        base_url: @host,
        url: "/2010-04-01/Accounts/#{config[:account_sid]}/Messages.json",
        method: :post,
        auth: {:basic, "#{config[:api_key_sid]}:#{config[:api_key_secret]}"},
        form: [To: to, From: config[:from_number], Body: body],
        retry: false
      ]
      |> Keyword.merge(Keyword.take(config, [:plug]))
      |> Req.request()

    case response do
      {:ok, %{status: 201}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        # Twilio's error code, not the body: the body repeats the member's number.
        code = if is_map(body), do: body["code"]
        Logger.warning("Twilio text failed: #{status} code #{inspect(code)}")
        {:error, status}

      {:error, exception} ->
        Logger.warning("Twilio text failed: #{Exception.message(exception)}")
        {:error, :unreachable}
    end
  end

  defp config, do: Application.get_env(:sarduty, __MODULE__, [])
end
