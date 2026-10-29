defmodule Web.HoneybadgerFilter do
  @moduledoc """
  Keeps secrets out of everything sent to Honeybadger: error reports and Insights
  events alike (#176).

  Honeybadger's `filter_keys` match whole names, and only at the top level of the
  params. This drops those keys at every level, plus any key whose name contains
  "key", "token", "code", "password", "secret", "authorization" or "cookie", so a new
  field like `new_d4h_access_key` can't slip past. Paths and URLs have their tokens and
  codes cut by Web.RequestLog.

  Honeybadger turns structs into maps when it sends them, so structs are scrubbed too. A
  crashed process's logger metadata can carry the whole request, with its headers and
  raw body, so a request keeps only its method and path, and a LiveView socket only its
  view. A schema loses its `redact: true` fields, and a changeset keeps only its errors.
  """

  @behaviour Honeybadger.Filter
  @behaviour Honeybadger.NoticeFilter
  @behaviour Honeybadger.EventFilter

  alias Honeybadger.NoticeFilter.Default
  alias Web.RequestLog

  @secret_words ~w(key token code password secret authorization cookie)
  @filtered "[FILTERED]"

  # Honeybadger.NoticeFilter: run the default filter, which calls the callbacks below,
  # then cut the request's path, which no callback sees.
  @impl Honeybadger.NoticeFilter
  def filter(%Honeybadger.Notice{} = notice) do
    notice = Default.filter(notice)

    case notice.request do
      %{url: url} = request when is_binary(url) ->
        host = get_in(request, [:cgi_data, "HTTP_HOST"])
        %{notice | request: %{request | url: RequestLog.filter_path(host, url)}}

      _no_request ->
        notice
    end
  end

  @impl Honeybadger.Filter
  def filter_params(params), do: scrub(params)

  @impl Honeybadger.Filter
  def filter_session(session), do: scrub(session)

  @impl Honeybadger.Filter
  def filter_context(context), do: scrub(context)

  @impl Honeybadger.Filter
  def filter_cgi_data(cgi) do
    host = cgi["HTTP_HOST"]

    cgi
    |> scrub()
    |> update_present("ORIGINAL_FULLPATH", &RequestLog.filter_path(host, &1))
    |> update_present("PATH_INFO", &(host |> RequestLog.filter_path("/" <> &1) |> trim_slash()))
    |> update_present("HTTP_REFERER", &filter_url/1)
  end

  # Ecto.InvalidChangesetError's message prints the changes, params, and changeset in
  # full, `redact: true` fields included: a member's email, phone, and address (#421).
  # Its errors come first, so keep those.
  @impl Honeybadger.Filter
  def filter_error_message(message) when is_binary(message) do
    message
    |> String.split(~r/\n\n(Applied changes|Params|Changeset)\n/, parts: 2)
    |> hd()
  end

  def filter_error_message(message), do: message

  @impl Honeybadger.Filter
  def filter_breadcrumbs(breadcrumbs), do: breadcrumbs

  # Honeybadger.NoticeFilter.Default calls this on the request headers too.
  def filter_map(map, _keys), do: scrub(map)

  @impl Honeybadger.EventFilter
  def filter_event(event), do: event

  # LiveView events carry the page's assigns, which can be a whole team's members with
  # their addresses. Honeybadger also prints an event it fails to send, so they reached
  # Fly's logs too. Never send them.
  @impl Honeybadger.EventFilter
  def filter_telemetry_event(data, raw, _event) do
    host = with %Plug.Conn{host: host} <- raw[:conn], do: host

    data
    |> Map.drop([:assigns, "assigns"])
    |> scrub()
    |> update_present(:request_path, &RequestLog.filter_path(host, &1))
    |> update_present(:url, &filter_url/1)
    |> Honeybadger.Utils.sanitize(remove_filtered: true)
  end

  @doc "Replaces the value of any secret key, at every level of maps, lists, and structs."
  def scrub(%Plug.Conn{} = conn) do
    %{
      method: conn.method,
      host: conn.host,
      request_path: RequestLog.filter_path(conn.host, conn.request_path)
    }
  end

  def scrub(%Phoenix.LiveView.Socket{view: view}), do: %{view: view}

  def scrub(%Ecto.Changeset{} = changeset),
    do: %{data: Map.get(changeset.data, :__struct__), errors: Keyword.keys(changeset.errors)}

  def scrub(%module{} = value) when module in [Date, DateTime, NaiveDateTime, Time], do: value

  def scrub(%module{} = struct) do
    redacted =
      if function_exported?(module, :__schema__, 1),
        do: module.__schema__(:redact_fields),
        else: []

    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Map.new(fn {key, value} ->
      if key in redacted, do: {key, @filtered}, else: {key, value}
    end)
    |> scrub()
  end

  def scrub(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if secret_key?(key), do: {key, @filtered}, else: {key, scrub(value)}
    end)
  end

  def scrub(list) when is_list(list), do: Enum.map(list, &scrub/1)

  def scrub({key, _value} = pair) when is_atom(key) or is_binary(key) do
    if secret_key?(key),
      do: {key, @filtered},
      else: pair |> Tuple.to_list() |> scrub() |> List.to_tuple()
  end

  def scrub(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> scrub() |> List.to_tuple()

  def scrub(value), do: value

  defp secret_key?(key) when is_atom(key) or is_binary(key) do
    name = key |> to_string() |> String.downcase()
    name in filter_keys() or String.contains?(name, @secret_words)
  end

  defp secret_key?(_key), do: false

  defp filter_keys do
    for key <- Honeybadger.get_env(:filter_keys) || [],
        do: key |> to_string() |> String.downcase()
  end

  defp filter_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{path: path} = uri when is_binary(path) ->
        URI.to_string(%{uri | path: RequestLog.filter_path(uri.host, path)})

      _no_path ->
        url
    end
  end

  defp filter_url(url), do: url

  defp update_present(map, key, fun) do
    case map do
      %{^key => value} when is_binary(value) -> Map.put(map, key, fun.(value))
      _missing -> map
    end
  end

  defp trim_slash("/" <> path), do: path
  defp trim_slash(path), do: path
end
