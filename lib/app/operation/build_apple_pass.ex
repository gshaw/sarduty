defmodule App.Operation.BuildApplePass do
  alias App.Model.DemoTeam
  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications
  alias App.Operation.LoadImage
  alias App.Repo
  alias App.Worker.UpdateCardWorker

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
  Expects the card with `member: [team: :organization]` preloaded. If the pass changed, the phones that
  hold it are told, since a refresh won't see the change once it's recorded here.
  """
  def call(%MemberCard{} = card, now) do
    if configured?() do
      card = Repo.preload(card, member: [team: :organization])
      config = :sarduty |> Application.get_env(:apple_pass) |> Map.new()
      card = MemberCard.ensure_authentication_token!(card)
      status = MemberCard.status(card, now)
      card = MemberCard.record_expires_at!(card, status)
      member = card.member
      qualifications = BuildCardQualifications.call(member.team, member, now)

      json = pass_json(card, status, qualifications, config)
      fingerprint = fingerprint(json)
      MemberCard.record_pass!(card, fingerprint, now)
      if fingerprint != card.pass_fingerprint, do: UpdateCardWorker.enqueue(card)

      files = %{
        "pass.json" => Jason.encode!(json),
        "icon.png" => LoadImage.logo(member.team, :icon),
        "logo.png" => LoadImage.logo(member.team, :logo),
        "thumbnail.png" => LoadImage.photo(member, :square)
      }

      {:ok, Service.ApplePass.package(files, config)}
    else
      {:error, :not_configured}
    end
  end

  @doc """
  The pass's `pass.json` as a map, for the card's `status` (MemberCard.status/3).
  `qualifications` comes from `BuildCardQualifications.summarize/3`.
  """
  def pass_json(%MemberCard{member: member} = card, status, qualifications, config) do
    team = member.team
    code = MemberCard.format_code(card.code)
    # A Try a demo card says so, front and centre (#857).
    sample? = DemoTeam.demo?(team)

    %{
      formatVersion: 1,
      webServiceURL: "#{Web.Endpoint.url()}/wallet",
      authenticationToken: card.authentication_token,
      passTypeIdentifier: config.pass_type_id,
      teamIdentifier: config.team_id,
      serialNumber: MemberCard.serial_number(card),
      organizationName: team.name,
      description: "#{team.name} member ID card",
      logoText: if(sample?, do: "Sample card", else: team.name),
      backgroundColor: @background_color,
      foregroundColor: @foreground_color,
      labelColor: @label_color,
      sharingProhibited: true,
      voided: status == :revoked,
      barcodes: barcodes(card, code, status),
      generic: %{
        # No header fields: they share the top row with the team name, which Wallet
        # then cuts short.
        primaryFields: [
          %{key: "name", label: MemberCard.name_label(status, sample?), value: member.name}
        ],
        secondaryFields: secondary_fields(card, status),
        backFields: back_fields(card, code, qualifications)
      }
    }
    |> put_expiration(MemberCard.expires_at(card, status))
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
  defp barcodes(card, code, status) do
    if status == :active do
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

  defp secondary_fields(%MemberCard{member: member}, status) do
    [
      %{
        key: "status",
        label: "Status",
        value: MemberCard.status_text(status),
        changeMessage: "Your card is now %@."
      },
      member.joined_at &&
        %{
          key: "member-since",
          label: "Member since",
          value: Service.Format.month_year(member.joined_at, member.team.timezone)
        },
      valid_until_field(member.team, status)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # Only an active card says how long it's good for. No changeMessage: it moves once a
  # month, and that update is silent.
  defp valid_until_field(team, :active) do
    if valid_until = MemberCard.valid_until(team) do
      %{
        key: "valid-until",
        label: "Valid until",
        value: Service.Format.month_year(valid_until, team.timezone)
      }
    end
  end

  defp valid_until_field(_team, _status), do: nil

  # Wallet marks the pass expired once this passes: when refreshes stop, or within three
  # months of the card going inactive (MemberCard.expires_at/2).
  defp put_expiration(json, nil), do: json

  defp put_expiration(json, expires_at),
    do: Map.put(json, :expirationDate, DateTime.to_iso8601(expires_at))

  defp back_fields(%MemberCard{member: %{team: team}}, code, qualifications) do
    List.flatten([
      %{
        key: "verify",
        label: "How to verify this card",
        value: MemberCard.how_to_check(code)
      },
      qualification_fields(qualifications, team.timezone),
      %{key: "checked", label: "Last updated", value: MemberCard.last_updated(team)},
      %{key: "issuer", label: "Issued by", value: MemberCard.issued_by(team)}
    ])
  end

  # A card made before pass updates has no token until its pass is next built.
  defp drop_web_service(json, nil), do: Map.drop(json, [:webServiceURL, :authenticationToken])
  defp drop_web_service(json, _token), do: json
end
