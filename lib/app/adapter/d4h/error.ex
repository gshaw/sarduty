defmodule App.Adapter.D4H.Error do
  defexception [:message, :status]

  @impl Exception
  def exception(%Req.Response{} = response) do
    # D4H error bodies carry a short "title", e.g. "Conflict", and often a "detail"
    # sentence that says why. Keep both so a refused write says what went wrong.
    reason =
      case response.body do
        %{"title" => title} = body when is_binary(title) -> with_detail(title, body["detail"])
        body when is_binary(body) -> body
        body when is_map(body) -> Jason.encode!(body)
        other -> inspect(other)
      end

    %__MODULE__{
      status: response.status,
      message: "D4H API error (#{response.status}): #{String.slice(reason, 0, 500)}"
    }
  end

  def exception(message) when is_binary(message), do: %__MODULE__{message: message}

  defp with_detail(title, detail) when is_binary(detail) do
    case String.trim(detail) do
      "" -> title
      ^title -> title
      detail -> "#{title}. #{detail}"
    end
  end

  defp with_detail(title, _detail), do: title
end
