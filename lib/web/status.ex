defmodule Web.Status.NotFound do
  defexception message: "💥 404 Not Found", plug_status: 404
end

defmodule Web.Status.TooManyRequests do
  defexception message: "💥 429 Too Many Requests", plug_status: 429
end

defmodule Web.Status.ServerError do
  defexception message: "💥 500 Server Error", plug_status: 500
end
