defmodule App.Operation.BuildApplePass do
  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications
  alias App.Operation.LoadPassImage
  alias App.Operation.PushPassUpdates

  # SAR Duty's navy and yellow, the same on every team's card.
  @background_color "rgb(28, 45, 66)"
  @foreground_color "rgb(255, 255, 255)"
  @label_color "rgb(255, 196, 0)"

  # Part of every fingerprint. Bump it to push every pass once, as when something outside
  # pass.json changes. 2: passes built for email or download had swallowed changes.
  # 3: square photos and PNG logos (#78).
  @fingerprint_version 3

  def configured? do
    config = Application.get_env(:sarduty, :apple_pass, [])
    Enum.all?([:pass_type_id, :team_id, :certificate, :private_key], &config[&1])
  end

  @doc """
  The signed `.pkpass` for a card, with the member's D4H photo and the team's logo.
  Expects the card with `member: :team` preloaded. If the pass changed, the phones that
  hold it are told, since a refresh won't see the change once it's recorded here.
  """
  def call(%MemberCard{} = card, now) do
    if configured?() do
      config = :sarduty |> Application.get_env(:apple_pass) |> Map.new()
      card = MemberCard.ensure_authentication_token!(card)
      member = card.member
      qualifications = BuildCardQualifications.call(member.team, member, now)

      json = pass_json(card, qualifications, config, now)
      fingerprint = fingerprint(json)
      MemberCard.record_pass!(card, fingerprint, now)
      if fingerprint != card.pass_fingerprint, do: PushPassUpdates.push_cards([card])

      files = %{
        "pass.json" => Jason.encode!(json),
        "icon.png" => LoadPassImage.logo(member.team.subdomain, :icon),
        "logo.png" => LoadPassImage.logo(member.team.subdomain, :logo),
        "thumbnail.png" => LoadPassImage.photo(member, :square)
      }

      {:ok, Service.ApplePass.package(files, config)}
    else
      {:error, :not_configured}
    end
  end

  @doc """
  The pass's `pass.json` as a map. `qualifications` comes from
  `BuildCardQualifications.summarize/3`.
  """
  def pass_json(%MemberCard{member: member} = card, qualifications, config, now) do
    team = member.team
    code = MemberCard.format_code(card.code)

    %{
      formatVersion: 1,
      webServiceURL: "#{Web.Endpoint.url()}/wallet",
      authenticationToken: card.authentication_token,
      passTypeIdentifier: config.pass_type_id,
      teamIdentifier: config.team_id,
      serialNumber: MemberCard.serial_number(card),
      organizationName: team.name,
      description: "#{team.name} member ID card",
      logoText: team.name,
      backgroundColor: @background_color,
      foregroundColor: @foreground_color,
      labelColor: @label_color,
      sharingProhibited: true,
      voided: MemberCard.status(card, now) == :revoked,
      barcodes: barcodes(card, code, now),
      generic: %{
        # No header fields: they share the top row with the team name, which Wallet
        # then cuts short.
        primaryFields: [
          %{key: "name", label: name_label(card, now), value: member.name}
        ],
        secondaryFields: secondary_fields(card, now),
        backFields: back_fields(team, code, qualifications)
      }
    }
    |> drop_web_service(card.authentication_token)
    |> Map.reject(fn {key, value} -> key == :barcodes and value == [] end)
  end

  @doc """
  A hash of what a member sees on the pass, less the last-refreshed date, which changes
  every day. Updates are pushed only when it changes.
  """
  def fingerprint(json) do
    back = Enum.reject(json.generic.backFields, &(&1.key == "checked"))

    json
    |> put_in([:generic, :backFields], back)
    |> Map.put(:fingerprint_version, @fingerprint_version)
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # One field per qualification, labelled with its name. A single field with a line per
  # qualification renders as a cramped table on the back.
  defp qualification_fields(qualifications, timezone) do
    for q <- qualifications do
      %{
        key: "qualification-#{q.name}",
        label: q.name,
        value: BuildCardQualifications.status_text(q, timezone),
        changeMessage: "#{q.name}: %@"
      }
    end
  end

  # Only an active card shows its QR code. Wallet dims a voided pass's code, which still
  # looks usable, so a card that can't pass a check shows none, and says why up top.
  defp barcodes(card, code, now) do
    if MemberCard.status(card, now) == :active do
      [
        %{
          format: "PKBarcodeFormatQR",
          message: card.code,
          messageEncoding: "iso-8859-1",
          altText: code
        }
      ]
    else
      []
    end
  end

  defp secondary_fields(%MemberCard{member: member} = card, now) do
    [
      %{
        key: "status",
        label: "STATUS",
        value: status_text(card, now),
        changeMessage: "Your card is now %@."
      },
      %{
        key: "member-since",
        label: "MEMBER SINCE",
        value: Service.Format.month_year(member.joined_at, member.team.timezone)
      },
      %{
        key: "member-for",
        label: "MEMBER FOR",
        value: Service.Format.months_or_years_distance(member.joined_at, now)
      }
    ]
  end

  defp back_fields(team, code, qualifications) do
    List.flatten([
      %{
        key: "verify",
        label: "How to check this card",
        value:
          "Open sarduty.com/verify on your own phone and scan the code, or type #{code}. " <>
            "Don't trust a link or a page you reached from the card."
      },
      qualification_fields(qualifications, team.timezone),
      %{key: "checked", label: "Last checked with D4H", value: last_checked(team)},
      %{
        key: "issuer",
        label: "Issued by",
        value: "#{team.name} through SAR Duty. Status comes from the team's D4H records."
      }
    ])
  end

  defp name_label(card, now) do
    case MemberCard.status(card, now) do
      :active -> "MEMBER"
      :inactive -> "NOT AN ACTIVE MEMBER"
      :revoked -> "CARD CANCELLED"
    end
  end

  defp status_text(card, now) do
    case MemberCard.status(card, now) do
      :active -> "Active"
      :inactive -> "Not active"
      :revoked -> "Cancelled"
    end
  end

  # A card made before pass updates has no token until its pass is next built.
  defp drop_web_service(json, nil), do: Map.drop(json, [:webServiceURL, :authenticationToken])
  defp drop_web_service(json, _token), do: json

  defp last_checked(%{d4h_refreshed_at: nil}), do: "Never"
  defp last_checked(team), do: Service.Format.date_long(team.d4h_refreshed_at, team.timezone)
end
