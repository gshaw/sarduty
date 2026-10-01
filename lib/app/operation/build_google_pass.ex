defmodule App.Operation.BuildGooglePass do
  alias App.Adapter.GoogleWallet
  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications

  # SAR Duty's navy, the same on every team's card, as on the Apple pass.
  @background_color "#1c2d42"

  def configured? do
    config = Application.get_env(:sarduty, :google_wallet, [])
    Enum.all?([:issuer_id, :service_account], &config[&1])
  end

  @doc """
  The issuer ID, the service account's credentials, the host the ids are made under,
  and whether passes carry the logo and photo. Dev and production share one issuer, so the host
  keeps their ids apart.
  """
  def config do
    config = :sarduty |> Application.get_env(:google_wallet) |> Map.new()

    %{
      issuer_id: config.issuer_id,
      credentials: GoogleWallet.credentials(config.service_account),
      host: Web.Endpoint.host(),
      images: Map.get(config, :images, false)
    }
  end

  @doc """
  Sends the card's pass to Google and returns the "Add to Google Wallet" link. Expects
  the card with `member: :team` preloaded.
  """
  def call(%MemberCard{} = card, now) do
    if configured?() do
      config = config()
      qualifications = BuildCardQualifications.call(card.member.team, card.member, now)
      object = pass_object(card, qualifications, config, now)

      with {:ok, token} <- GoogleWallet.access_token(config.credentials, now),
           :ok <- GoogleWallet.upsert(token, "genericClass", pass_class(config)),
           :ok <- GoogleWallet.upsert(token, "genericObject", object) do
        MemberCard.record_google_pass!(card, fingerprint(object))
        {:ok, GoogleWallet.save_url(object.id, config.credentials, now)}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  The class every card shares. Its template puts status, member since, and valid until
  in a row on the front; the rest of the text shows under Details.
  """
  def pass_class(config) do
    %{
      id: "#{config.issuer_id}.#{config.host}-member-card",
      # A card is for one person, like Apple's sharingProhibited.
      multipleDevicesAndHoldersAllowedStatus: "ONE_USER_ALL_DEVICES",
      classTemplateInfo: %{
        cardTemplateOverride: %{
          cardRowTemplateInfos: [
            %{
              threeItems: %{
                startItem: template_item("status"),
                middleItem: template_item("member_since"),
                endItem: template_item("valid_until")
              }
            }
          ]
        }
      }
    }
  end

  defp template_item(id) do
    %{firstValue: %{fields: [%{fieldPath: "object.textModulesData['#{id}']"}]}}
  end

  @doc """
  The card's Google Wallet object as a map. `qualifications` comes from
  `BuildCardQualifications.summarize/3`.
  """
  def pass_object(%MemberCard{member: member} = card, qualifications, config, now) do
    team = member.team
    status = MemberCard.status(card, now)

    %{
      id: object_id(card, config),
      classId: pass_class(config).id,
      # An expired pass moves to "Expired passes" in Wallet.
      state: if(status == :revoked, do: "EXPIRED", else: "ACTIVE"),
      hexBackgroundColor: @background_color,
      cardTitle: localized(team.name),
      subheader: localized(name_label(status)),
      header: localized(member.name),
      textModulesData: texts(card, qualifications, status)
    }
    |> put_valid_time(team)
    |> put_barcode(card, status)
    |> put_images(card, status, config)
  end

  defp texts(%MemberCard{member: member} = card, qualifications, status) do
    team = member.team
    issuer = "#{team.name} through SAR Duty. Status comes from the team's D4H records."

    List.flatten([
      text("status", "Status", status_text(status)),
      text("member_since", "Member since", member_since(member)),
      valid_until_text(team, status),
      text(
        "verify",
        "How to check this card",
        MemberCard.how_to_check(MemberCard.format_code(card.code))
      ),
      qualification_texts(qualifications, team.timezone),
      text("checked", "Last checked with D4H", last_checked(team)),
      text("issuer", "Issued by", issuer)
    ])
  end

  @doc """
  The Wallet object id. A replacement card gets a new one: Google has no per-phone
  secret to tell which card a phone holds, so the old pass expires and the new one is
  added beside it.
  """
  def object_id(%MemberCard{id: id}, config), do: "#{config.issuer_id}.#{config.host}-card-#{id}"

  @doc """
  A hash of what a member sees on the pass, less the last-refreshed date, which changes
  every day. The pass is sent to Google only when this changes.
  """
  def fingerprint(object) do
    object
    |> Map.update!(:textModulesData, fn texts -> Enum.reject(texts, &(&1.id == "checked")) end)
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Only an active card shows its QR code, as on the Apple pass. It opens the card's
  # /verify page; only the code is printed under it.
  defp put_barcode(object, card, :active) do
    Map.put(object, :barcode, %{
      type: "QR_CODE",
      value: MemberCard.qr_url(card.code, Web.Endpoint.url()),
      alternateText: MemberCard.format_code(card.code)
    })
  end

  defp put_barcode(object, _card, _status), do: object

  # Wallet moves the pass to "Expired passes" once this passes, which happens only if
  # refreshes stop.
  defp put_valid_time(object, team) do
    case MemberCard.valid_until(team) do
      nil ->
        object

      valid_until ->
        Map.put(object, :validTimeInterval, %{end: %{date: DateTime.to_iso8601(valid_until)}})
    end
  end

  # Only an active card says how long it's good for.
  defp valid_until_text(team, :active) do
    case MemberCard.valid_until(team) do
      nil ->
        []

      valid_until ->
        text("valid_until", "Valid until", Service.Format.month_year(valid_until, team.timezone))
    end
  end

  defp valid_until_text(_team, _status), do: []

  # Google loads images from URLs it can reach, so dev passes have none. The team logo
  # sits in the round spot beside the team name, and the photo in the banner under the
  # QR code, from the public URL /verify uses. A cancelled card's photo URL 404s.
  defp put_images(object, _card, _status, %{images: false}), do: object

  defp put_images(object, card, status, _config) do
    team = card.member.team
    url = Web.Endpoint.url()

    object
    |> Map.put(:logo, %{
      sourceUri: %{uri: "#{url}/teams/#{team.subdomain}/logo"},
      contentDescription: localized("#{team.name} logo")
    })
    |> put_banner(card, status, url)
  end

  defp put_banner(object, _card, :revoked, _url), do: object

  defp put_banner(object, card, _status, url) do
    Map.put(object, :heroImage, %{
      sourceUri: %{uri: "#{url}/verify/#{card.code}/banner"},
      contentDescription: localized("Photo of #{card.member.name}")
    })
  end

  # Text module ids are letters, digits, and underscores, so qualifications go by
  # position, not name.
  defp qualification_texts(qualifications, timezone) do
    for {q, index} <- Enum.with_index(qualifications) do
      text("qualification_#{index}", q.name, BuildCardQualifications.status_text(q, timezone))
    end
  end

  defp text(id, header, body), do: %{id: id, header: header, body: body}

  defp localized(value), do: %{defaultValue: %{language: "en", value: value}}

  defp name_label(:active), do: "Member"
  defp name_label(:inactive), do: "Not an active member"
  defp name_label(:revoked), do: "Card cancelled"

  defp status_text(:active), do: "Active"
  defp status_text(:inactive), do: "Not active"
  defp status_text(:revoked), do: "Cancelled"

  defp member_since(member), do: Service.Format.month_year(member.joined_at, member.team.timezone)

  defp last_checked(%{d4h_refreshed_at: nil}), do: "Never"
  defp last_checked(team), do: Service.Format.date_long(team.d4h_refreshed_at, team.timezone)
end
