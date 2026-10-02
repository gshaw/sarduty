defmodule App.Operation.BuildApplePass do
  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications
  alias App.Operation.LoadImage
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
        "icon.png" => LoadImage.logo(member.team.subdomain, :icon),
        "logo.png" => LoadImage.logo(member.team.subdomain, :logo),
        "thumbnail.png" => LoadImage.photo(member, :square)
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
        backFields: back_fields(card, code, qualifications)
      }
    }
    |> put_expiration(team)
    |> drop_web_service(card.authentication_token)
    |> Map.reject(fn {key, value} -> key == :barcodes and value == [] end)
  end

  @doc """
  A hash of what a member sees on the pass, less the last-refreshed date, which changes
  every day, and the test update time, which a manager pushes by hand. Updates are
  pushed only when it changes.
  """
  def fingerprint(json) do
    back = Enum.reject(json.generic.backFields, &(&1.key in ["checked", "test"]))

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
          message: MemberCard.qr_url(card.code, Web.VerifyHost.url()),
          messageEncoding: "iso-8859-1",
          # Just the code: Wallet widens its white box to fit this text, and shows only
          # the first line of it. How to check the card is on the back.
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
      valid_until_field(card, now)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # Only an active card says how long it's good for. No changeMessage: it moves once a
  # month, and that update is silent.
  defp valid_until_field(%MemberCard{member: member} = card, now) do
    valid_until = MemberCard.valid_until(member.team)

    if valid_until && MemberCard.status(card, now) == :active do
      %{
        key: "valid-until",
        label: "VALID UNTIL",
        value: Service.Format.month_year(valid_until, member.team.timezone)
      }
    end
  end

  # Wallet marks the pass expired once this passes, which happens only if refreshes stop.
  defp put_expiration(json, team) do
    case MemberCard.valid_until(team) do
      nil -> json
      valid_until -> Map.put(json, :expirationDate, DateTime.to_iso8601(valid_until))
    end
  end

  defp back_fields(%MemberCard{member: %{team: team}} = card, code, qualifications) do
    List.flatten([
      %{
        key: "verify",
        label: "How to check this card",
        value: MemberCard.how_to_check(code)
      },
      qualification_fields(qualifications, team.timezone),
      %{key: "checked", label: "Last updated", value: last_checked(team)},
      test_field(card, team),
      %{
        key: "issuer",
        label: "Issued by",
        value: "#{team.name} through SAR Duty. Status comes from the team's records."
      }
    ])
  end

  # Sent from the ID Card tab. The changeMessage puts a notice on the lock screen, which
  # is how a manager sees the update arrive.
  defp test_field(%MemberCard{pass_test_at: nil}, _team), do: []

  defp test_field(card, team) do
    %{
      key: "test",
      label: "Test update",
      value: Service.Format.month_day_time_seconds(card.pass_test_at, team.timezone),
      changeMessage: "SAR Duty test update %@"
    }
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
