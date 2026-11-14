defmodule Web.TeamController do
  use Web, :controller

  alias App.Model.Team
  alias App.Operation.LoadImage

  @doc """
  The logo's full URL, since the verify site is another host. `?v=` changes with the logo
  (`logo_at`), so a new one shows at once. Shapes are as `logo/2` sends them.
  """
  def logo_url(%Team{} = team, shape \\ :round) do
    query =
      Enum.reject(
        [shape: shape_param(shape), v: team.logo_at && DateTime.to_unix(team.logo_at)],
        fn {_key, value} -> is_nil(value) end
      )

    path = if query == [], do: ~p"/teams/#{team}/logo", else: ~p"/teams/#{team}/logo?#{query}"
    Web.Endpoint.url() <> path
  end

  defp shape_param(:round), do: nil
  defp shape_param(:square), do: "square"
  defp shape_param(:fit), do: "fit"

  # The team logo padded square, for the round spot on Google passes. ?shape=square
  # leaves off the margin the circle needs, for the dashboards and verify page. ?shape=fit
  # is the logo at its own shape with no padding, for the Dashboard's head, which sizes
  # it by height so the gap beside it is the gap. Public, because Google loads it from
  # this URL. A team without a logo gets SAR Duty's. A URL with ?v= names one logo, so it
  # caches for a year; one without may be a team whose logo is about to change.
  def logo(conn, %{"subdomain" => subdomain} = params) do
    shape =
      case params["shape"] do
        "square" -> :square
        "fit" -> :logo
        _other -> :round
      end

    cache =
      if params["v"],
        do: "public, max-age=31536000, immutable",
        else: "public, max-age=300"

    case Team.get_by(subdomain: subdomain) do
      %Team{} = team ->
        conn
        |> put_resp_header("cache-control", cache)
        |> put_resp_content_type("image/png", nil)
        |> send_resp(200, LoadImage.logo(team, shape))

      nil ->
        send_resp(conn, :not_found, "")
    end
  end

  @doc """
  The logo as SAR Duty saved it, to download from Change logo (#1075): the file the
  team's records gave, or the one saved from Change logo.
  """
  def original_logo(conn, _params) do
    team = conn.assigns.current_team

    case team.subdomain |> Team.logo_file() |> then(&(&1 && File.read(&1))) do
      {:ok, bytes} ->
        {type, extension} = image_type(bytes)
        filename = String.replace("#{team.name} logo.#{extension}", ~r/["\\\r\n]/, "")

        conn
        |> put_resp_content_type(type, nil)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, bytes)

      _none ->
        send_resp(conn, :not_found, "")
    end
  end

  # cspell:ignore webp -- the WebP image format, by its file signature
  # D4H keeps the file as it was sent, so a logo saved in D4H's web app may be a JPEG.
  defp image_type(<<0x89, "PNG", _rest::binary>>), do: {"image/png", "png"}
  defp image_type(<<0xFF, 0xD8, _rest::binary>>), do: {"image/jpeg", "jpg"}

  defp image_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: {"image/webp", "webp"}

  defp image_type(_bytes), do: {"application/octet-stream", "bin"}
end
