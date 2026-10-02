defmodule App.Operation.LoadImage do
  @moduledoc """
  A member's photo or a team's logo as a PNG, shaped for a pass, a page, or a letter. Falls back to
  the placeholder photo or SAR Duty's logo when D4H has none or the image won't decode,
  so a bad image never fails a pass.
  """

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Team

  require Logger

  # The passes' navy, behind the photo in Google's banner.
  @navy "#1c2d42"

  # Google's recommended hero image size.
  @banner_width 1032
  @banner_height 336

  @doc """
  `:square` for /verify, the member page, and the Apple thumbnail; `:banner` for the
  Google hero image. Fetches with the team's D4H key unless given another context.
  Expects the member with `:team` preloaded.
  """
  def photo(%Member{} = member, shape, d4h \\ nil) do
    d4h = d4h || D4H.build_context_from_team(member.team)

    bytes =
      case D4H.fetch_member_image(d4h, member.d4h_member_id) do
        {:ok, image, _filename} -> image
        {:error, _response} -> nil
      end

    shape_or_default(bytes, &shape_photo(&1, shape), default_photo())
  end

  @doc """
  `:round` for Google's circle, padded so the circle clips nothing; `:square` for the
  tax credit letter, the dashboards, and the verify page; `:icon` for the Apple icon; `:logo` for the Apple
  logo, which Wallet fits in a wide strip.
  """
  def logo(subdomain, shape) do
    bytes = if path = Team.logo_file(subdomain), do: File.read!(path)
    shape_or_default(bytes, &shape_logo(&1, shape), default_logo())
  end

  defp shape_or_default(nil, fun, default), do: shape!(default, fun)

  defp shape_or_default(bytes, fun, default) do
    case fun.(bytes) do
      {:ok, png} ->
        png

      {:error, reason} ->
        Logger.warning("pass image failed, using the default: #{inspect(reason)}")
        shape!(default, fun)
    end
  end

  defp shape!(bytes, fun) do
    {:ok, png} = fun.(bytes)
    png
  end

  defp shape_photo(bytes, :square), do: Service.Image.square(bytes)

  defp shape_photo(bytes, :banner),
    do: Service.Image.banner(bytes, @banner_width, @banner_height, @navy)

  defp shape_logo(bytes, :round), do: Service.Image.pad_square(bytes, 660, margin: 0.12)
  defp shape_logo(bytes, :square), do: Service.Image.pad_square(bytes, 660)
  defp shape_logo(bytes, :icon), do: Service.Image.pad_square(bytes, 180)
  defp shape_logo(bytes, :logo), do: Service.Image.png(bytes, 480)

  defp default_photo, do: read_priv("static/images/member.png")
  defp default_logo, do: read_priv("apple/sarduty_logo.png")

  defp read_priv(path),
    do: :sarduty |> Application.app_dir(Path.join("priv", path)) |> File.read!()
end
