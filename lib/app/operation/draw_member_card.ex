defmodule App.Operation.DrawMemberCard do
  @moduledoc """
  An ID card drawn by SAR Duty, not a Wallet (#973): the card page's pictures of its
  front and back, which Save image saves, and Print ID card's PDF, both sides at actual
  size to cut out. One Typst drawing, `priv/typst/member_card.typ`, makes all three, so
  they never disagree. Its sides are CR80, 85.60 × 53.98 mm, the size of a plastic ID
  card, so a printed copy fits any card holder.

  The front has the team, the photo, the name, Member since, the day the card was issued,
  and the QR code. The back has the code again, the name, and what the Wallet passes' backs
  say about verifying and who issued the card. No status, Valid until, Last updated, or
  endorsements: a copy never updates, so they would freeze. The QR code is the real check,
  and the verify page lists the endorsements. Nothing on it changes with the day it's
  drawn, so every copy of a card is the same.

  Only for a live card in good standing (`MemberCard.link_status/2`); the routes check.
  """

  alias App.Model.DemoTeam
  alias App.Model.MemberCard
  alias App.Operation.LoadImage
  alias App.Repo
  alias Service.Format
  alias Service.Typst

  # 85.6 mm at 400 pixels an inch is 1348 pixels: sharp at the page's 340 on a 2x screen,
  # and printed from Photos.
  @ppi 400

  @help "Cut out both sides on the dashed lines. Each is the size of a plastic ID card, " <>
          "so it fits a standard badge holder. Put them back to back, or laminate them together."

  @doc """
  `{:ok, bytes}` or `{:error, reason}`: the `:front` or the `:back` as a PNG, or `:print`,
  a Letter page with both sides, as a PDF. Fetches the member's photo from D4H, as a pass
  does.
  """
  def call(%MemberCard{} = card, side) when side in [:front, :back, :print] do
    card = Repo.preload(card, member: [team: :organization])
    member = card.member
    team = member.team

    files = %{
      "card.typ" => template() |> File.read!(),
      "card.json" => card |> card_data(DemoTeam.demo?(team)) |> Jason.encode!(),
      "photo.png" => LoadImage.photo(member, :square),
      "logo.png" => LoadImage.logo(team, :square),
      "qr.svg" =>
        card.code |> MemberCard.qr_url(Web.VerifyHost.url()) |> EQRCode.encode() |> EQRCode.svg()
    }

    case side do
      :print -> side |> source() |> Typst.compile(files)
      _side -> side |> source() |> Typst.compile(files, png: @ppi)
    end
  end

  @doc """
  Pure. What the drawing writes, as the card.json the template reads. `card` has
  `member: [team: :organization]`; `sample?` marks a Try a demo card, as its passes are
  marked (#857).
  """
  def card_data(%MemberCard{member: member} = card, sample?) do
    team = member.team
    timezone = team.timezone
    code = MemberCard.format_code(card.code)

    %{
      team: if(sample?, do: "Sample card", else: team.name),
      name_label: if(sample?, do: MemberCard.name_label(:active, true)),
      name: member.name,
      member_since: member.joined_at && Format.month_year(member.joined_at, timezone),
      issued: Format.date_short(card.inserted_at, timezone),
      code: code,
      notes: [
        ["How to verify this card", MemberCard.how_to_check(code)],
        ["Issued by", MemberCard.issuer(team)]
      ],
      sheet_title: "#{team.name} ID card · #{member.name}",
      sheet_help: @help
    }
  end

  defp source(:print), do: ~s|#import "card.typ": *\n#sheet(json("card.json"))\n|

  defp source(side),
    do:
      ~s|#import "card.typ": *\n#set page(width: auto, height: auto, margin: 0pt)\n| <>
        ~s|##{side}(json("card.json"))\n|

  defp template, do: Application.app_dir(:sarduty, "priv/typst/member_card.typ")
end
