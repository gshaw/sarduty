defmodule App.Adapter.CloudflareEmail do
  @moduledoc """
  Swoosh adapter for Cloudflare Email Sending's REST API. Swoosh ships no Cloudflare
  adapter yet.

  https://developers.cloudflare.com/email-service/api/send-emails/rest-api/

  Config: `:account_id`, `:api_token` (a token with the Email Sending: Edit permission),
  and `:req_options`, merged into the request so tests can pass a `Req.Test` plug.

  A recipient on the account's suppression list fails the whole send (code 10205). When
  the block never ends, deliver/2 returns `{:error, {:email_problem, problem}}`, one of
  `App.Model.Member`'s email problems, so App.Mailer can note it on the member. A block
  that ends on its own is an ordinary refusal.

  https://developers.cloudflare.com/email-service/concepts/suppressions/
  """

  use Swoosh.Adapter, required_config: [:account_id, :api_token]

  alias Swoosh.Email

  @base_url "https://api.cloudflare.com/client/v4"

  # Cloudflare's code for a send refused because a recipient is suppressed.
  @suppressed 10_205

  @impl Swoosh.Adapter
  def deliver(%Email{} = email, config) do
    config
    |> request("send", json: payload(email))
    |> Req.post()
    |> sent(email, config)
  end

  # The account's Email Sending endpoint `path`, with the token and any test options.
  defp request(config, path, options) do
    [
      url: "#{@base_url}/accounts/#{config[:account_id]}/email/sending/#{path}",
      auth: {:bearer, config[:api_token]}
    ]
    |> Keyword.merge(options)
    |> Keyword.merge(config[:req_options] || [])
  end

  defp sent(
         {:ok, %Req.Response{status: 200, body: %{"success" => true, "result" => result}}},
         _email,
         _config
       ) do
    {:ok,
     %{
       id: result["message_id"],
       delivered: result["delivered"],
       queued: result["queued"],
       permanent_bounces: result["permanent_bounces"]
     }}
  end

  defp sent({:ok, %Req.Response{status: status, body: body}}, email, config) do
    if suppressed?(body),
      do: suppressed_error(email, config, {status, body}),
      else: {:error, {status, body}}
  end

  defp sent({:error, exception}, _email, _config), do: {:error, exception}

  defp suppressed?(%{"errors" => errors}) when is_list(errors),
    do: Enum.any?(errors, &(&1["code"] == @suppressed))

  defp suppressed?(_body), do: false

  # The refusal doesn't say why, so ask the suppression list. A lookup that fails, or an
  # email to several people, is `:blocked`: App.Mailer clears it once a send works.
  defp suppressed_error(email, config, refusal) do
    with [{_name, address}] <- email.to ++ email.cc ++ email.bcc,
         {:ok, suppressions} <- suppressions(address, config) do
      case problem(suppressions) do
        nil -> {:error, refusal}
        problem -> {:error, {:email_problem, problem}}
      end
    else
      _several_or_failed -> {:error, {:email_problem, :blocked}}
    end
  end

  defp suppressions(address, config) do
    response = config |> request("suppressions", params: [email: address]) |> Req.get()

    case response do
      {:ok, %Req.Response{status: 200, body: %{"result" => result}}} when is_list(result) ->
        {:ok, result}

      _failed ->
        :error
    end
  end

  # Only a block that never ends is a problem; one that expires clears on its own. A hard
  # bounce that never ends means the mailbox or its domain does not exist. An empty list
  # says nothing about why Cloudflare refused it.
  defp problem([]), do: :blocked

  defp problem(suppressions) do
    reasons = for %{"expires_at" => nil, "reason" => reason} <- suppressions, do: reason

    cond do
      reasons == [] -> nil
      "hard_bounce" in reasons -> :no_such_address
      "complaint" in reasons -> :spam_report
      true -> :blocked
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
