defmodule App.Operation.BuildApplePass do
  alias App.Adapter.D4H
  alias App.Model.MemberCard
  alias App.Model.Team

  # SAR Duty's navy and yellow, the same on every team's card.
  @background_color "rgb(28, 45, 66)"
  @foreground_color "rgb(255, 255, 255)"
  @label_color "rgb(255, 196, 0)"

  def configured? do
    config = Application.get_env(:sarduty, :apple_pass, [])
    Enum.all?([:pass_type_id, :team_id, :certificate, :private_key], &config[&1])
  end

  @doc """
  The signed `.pkpass` for a card, with the member's D4H photo and the team's logo.
  Expects the card with `member: :team` preloaded.
  """
  def call(%MemberCard{} = card, now) do
    if configured?() do
      config = :sarduty |> Application.get_env(:apple_pass) |> Map.new()
      member = card.member
      logo = (Team.logo_file(member.team.subdomain) || default_logo_path()) |> File.read!()

      files = %{
        "pass.json" => card |> pass_json(config, now) |> Jason.encode!(),
        "icon.png" => logo,
        "logo.png" => logo,
        "thumbnail.png" => photo(member)
      }

      {:ok, Service.ApplePass.package(files, config)}
    else
      {:error, :not_configured}
    end
  end

  @doc "The pass's `pass.json` as a map."
  def pass_json(%MemberCard{member: member} = card, config, now) do
    team = member.team
    code = MemberCard.format_code(card.code)

    %{
      formatVersion: 1,
      passTypeIdentifier: config.pass_type_id,
      teamIdentifier: config.team_id,
      serialNumber: "member-card-#{card.id}",
      organizationName: team.name,
      description: "#{team.name} member ID card",
      logoText: team.name,
      backgroundColor: @background_color,
      foregroundColor: @foreground_color,
      labelColor: @label_color,
      sharingProhibited: true,
      voided: MemberCard.status(card, now) == :revoked,
      barcodes: [
        %{
          format: "PKBarcodeFormatQR",
          message: card.code,
          messageEncoding: "iso-8859-1",
          altText: code
        }
      ],
      generic: %{
        headerFields: [
          %{key: "status", label: "STATUS", value: status_text(card, now)}
        ],
        primaryFields: [
          %{key: "name", label: "MEMBER", value: member.name}
        ],
        secondaryFields: [
          %{
            key: "member-since",
            label: "MEMBER SINCE",
            value: Service.Format.month_year(member.joined_at, team.timezone)
          },
          %{
            key: "member-for",
            label: "MEMBER FOR",
            value: Service.Format.months_or_years_distance(member.joined_at, now)
          }
        ],
        backFields: [
          %{
            key: "verify",
            label: "How to check this card",
            value:
              "Open sarduty.com/verify on your own phone and scan the code, or type #{code}. " <>
                "Don't trust a link or a page you reached from the card."
          },
          %{key: "checked", label: "Last checked with D4H", value: last_checked(team)},
          %{
            key: "issuer",
            label: "Issued by",
            value: "#{team.name} through SAR Duty. Status comes from the team's D4H records."
          }
        ]
      }
    }
  end

  defp status_text(card, now) do
    if MemberCard.status(card, now) == :active, do: "Active", else: "Not active"
  end

  defp last_checked(%{d4h_refreshed_at: nil}), do: "Never"
  defp last_checked(team), do: Service.Format.date_long(team.d4h_refreshed_at, team.timezone)

  defp photo(member) do
    d4h = D4H.build_context_from_team(member.team)

    case D4H.fetch_member_image(d4h, member.d4h_member_id) do
      {:ok, image, _filename} -> image
      {:error, _response} -> File.read!(default_photo_path())
    end
  end

  defp default_logo_path, do: Application.app_dir(:sarduty, "priv/apple/sarduty_logo.png")
  defp default_photo_path, do: Application.app_dir(:sarduty, "priv/static/images/member.png")
end
