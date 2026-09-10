defmodule App.Adapter.D4H.Error do
  defexception [:message, :status]

  @impl Exception
  def exception(%Req.Response{} = response) do
    body =
      case response.body do
        body when is_binary(body) -> body
        body when is_map(body) -> Jason.encode!(body)
        other -> inspect(other)
      end

    %__MODULE__{
      status: response.status,
      message: "D4H API error (#{response.status}): #{String.slice(body, 0, 500)}"
    }
  end

  def exception(message) when is_binary(message), do: %__MODULE__{message: message}
end
