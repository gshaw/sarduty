defmodule App.Operation.DrawMemberCard do
  @moduledoc """
  An ID card drawn by SAR Duty, not a Wallet (#973): the card page's pictures of its
  front and back, which Save image saves, and Print ID card's PDF, both sides at actual
  size to cut out. One Typst drawing, `priv/typst/member_card.typ`, makes all three, so
  they never disagree, and its sides are 54 mm wide, a badge holder's width.

  The front shows what the pass's front does, less Valid until: a copy never updates,
  so it would freeze, and look expired on an active member or current on a retired one.
  The day it was drawn takes its place, and the QR code is the real check. The back
  holds what the pass's back does, as tall as its list of endorsements.

  Only for a live card in good standing (`MemberCard.link_status/2`); the routes check.
  """

  alias App.Model.DemoTeam
  alias App.Model.MemberCard
  alias App.Operation.BuildCardQualifications
  alias App.Operation.LoadImage
  alias App.Repo
  alias Service.Format
  alias Service.Typst

  # 54 mm at 400 pixels an inch is 850 pixels: sharp at the page's 340 on a 2x screen,
  # and printed from Photos.
  @ppi 400

  @help "Cut out both sides on the dashed lines. Put them back to back in a badge holder, " <>
          "or laminate them together."

  @doc """
  `{:ok, bytes}` or `{:error, reason}`: the `:front` or the `:back` as a PNG, or `:print`,
  a Letter page with both sides in black on white, as a PDF. Fetches the member's photo
  from D4H, as a pass does.
  """
  def call(%MemberCard{} = card, side, now) when side in [:front, :back, :print] do
    card = Repo.preload(card, member: [team: :organization])
    member = card.member
    team = member.team
    qualifications = BuildCardQualifications.call(team, member, now)
    sample? = DemoTeam.demo?(team)

    files = %{
      "card.typ" => template() |> File.read!(),
      "card.json" => card |> card_data(qualifications, sample?, now) |> Jason.encode!(),
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
  `member: [team: :organization]`; `qualifications` is from BuildCardQualifications;
  `sample?` marks a Try a demo card, as its passes are marked (#857).
  """
  def card_data(%MemberCard{member: member} = card, qualifications, sample?, now) do
    team = member.team
    timezone = team.timezone
    code = MemberCard.format_code(card.code)

    %{
      team: if(sample?, do: "Sample card", else: team.name),
      name_label: MemberCard.name_label(:active, sample?),
      name: member.name,
      status: MemberCard.status_text(:active),
      member_since: member.joined_at && Format.month_year(member.joined_at, timezone),
      code: code,
      made: "#{Format.date_short(now, timezone)} · Scan the code to verify it",
      endorsements: for(q <- qualifications, do: %{name: q.name, expires: expires(q, timezone)}),
      notes: [
        ["How to verify this card", MemberCard.how_to_check(code)],
        ["Last updated", MemberCard.last_updated(team)],
        ["Issued by", MemberCard.issued_by(team)]
      ],
      sheet_title: "#{team.name} ID card · #{member.name}",
      sheet_help: @help
    }
  end

  defp expires(qualification, timezone) do
    case BuildCardQualifications.status_text(qualification, timezone) do
      "" -> "No expiry"
      month -> "Expires #{month}"
    end
  end

  defp source(:print), do: ~s|#import "card.typ": *\n#sheet(json("card.json"))\n|

  defp source(side),
    do:
      ~s|#import "card.typ": *\n#set page(width: auto, height: auto, margin: 0pt)\n| <>
        ~s|##{side}(json("card.json"))\n|

  defp template, do: Application.app_dir(:sarduty, "priv/typst/member_card.typ")
end
