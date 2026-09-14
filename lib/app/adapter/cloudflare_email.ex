defmodule App.Adapter.CloudflareEmail do
  @moduledoc """
  Swoosh adapter for Cloudflare Email Sending's REST API. Swoosh ships no Cloudflare
  adapter yet.

  https://developers.cloudflare.com/email-service/api/send-emails/rest-api/

  Config: `:account_id`, `:api_token` (a token with the Email Sending: Edit permission),
  and `:req_options`, merged into the request so tests can pass a `Req.Test` plug.
  """

  use Swoosh.Adapter, required_config: [:account_id, :api_token]

  alias Swoosh.Email

  @base_url "https://api.cloudflare.com/client/v4"

  @impl Swoosh.Adapter
  def deliver(%Email{} = email, config) do
    response =
      [
        url: "#{@base_url}/accounts/#{config[:account_id]}/email/sending/send",
        auth: {:bearer, config[:api_token]},
        json: payload(email)
      ]
      |> Keyword.merge(config[:req_options] || [])
      |> Req.post()

    case response do
      {:ok, %Req.Response{status: 200, body: %{"success" => true, "result" => result}}} ->
        {:ok,
         %{
           id: result["message_id"],
           delivered: result["delivered"],
           queued: result["queued"],
           permanent_bounces: result["permanent_bounces"]
         }}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp payload(email) do
    %{
      from: address(email.from),
      to: Enum.map(email.to, &address/1),
      cc: Enum.map(email.cc, &address/1),
      bcc: Enum.map(email.bcc, &address/1),
      reply_to: email.reply_to && address(email.reply_to),
      subject: email.subject,
      text: email.text_body,
      html: email.html_body,
      headers: email.headers,
      attachments: Enum.map(email.attachments, &attachment/1)
    }
    # The API rejects unknown keys, so leave out the empty ones rather than send nulls.
    |> Map.reject(fn {_key, value} -> value in [nil, [], %{}] end)
  end

  defp address({name, address}) when name in [nil, ""], do: address
  defp address({name, address}), do: %{address: address, name: name}

  defp attachment(%Swoosh.Attachment{} = attachment) do
    base = %{
      content: Swoosh.Attachment.get_content(attachment, :base64),
      filename: attachment.filename,
      type: attachment.content_type
    }

    case attachment.type do
      :inline -> Map.merge(base, %{disposition: "inline", content_id: attachment.cid})
      :attachment -> Map.put(base, :disposition, "attachment")
    end
  end
end
