defmodule App.Operation.DrawMemberCard do
  @moduledoc """
  An ID card drawn by SAR Duty, not a Wallet (#973): the card page's picture, which
  Save image saves, and Print ID card's PDF, both sides at actual size to cut out. One
  Typst drawing, `priv/typst/member_card.typ`, makes both, from the same facts.

  The picture is the front as the Wallet passes draw theirs, upright in navy, so a member
  can show the page or the picture as they would the pass. The printed sides are CR80,
  85.60 × 53.98 mm, the size of a plastic ID card, so they fit any card holder: white
  under a navy line, which any team logo shows on and any printer prints.

  Both fronts have the team, the photo, the name, Member since, the day the card was
  issued, and the QR code. The printed back has the code again, the name, and what the
  Wallet passes' backs say about verifying and who issued the card. No status, Valid
  until, Last updated, or endorsements: a copy never updates, so they would freeze. The
  QR code is the real check, and the verify page lists the endorsements. Nothing changes
  with the day it's drawn, so every copy of a card is the same.

  Print ID card is only for a live card in good standing (`MemberCard.link_status/2`);
  the routes check. A replaced, cancelled, or not active card's picture draws grey, with
  its state in the QR code's place, for its page.
  """

  alias App.Model.DemoTeam
  alias App.Model.MemberCard
  alias App.Operation.LoadImage
  alias App.Repo
  alias Service.Format
  alias Service.Typst

  # 54 mm at 400 pixels an inch is 850 pixels: sharp at the page's 340 on a 2x screen,
  # and shown or printed from Photos.
  @ppi 400

  @help "Cut out both sides on the dashed lines. Each is the size of a plastic ID card, " <>
          "so it fits a standard badge holder. Put them back to back, or laminate them together."

  @doc """
  `{:ok, bytes}` or `{:error, reason}`: the `:image` as a PNG, or `:print`, a Letter page
  with both sides, as a PDF. `status` is the card's `MemberCard.link_status/2`. Fetches
  the member's photo from D4H, as a pass does.
  """
  def call(%MemberCard{} = card, side, status \\ :active)
      when side == :image or (side == :print and status == :active) do
    card = Repo.preload(card, member: [team: :organization])
    member = card.member
    team = member.team

    files = %{
      "card.typ" => template() |> File.read!(),
      "card.json" => card |> card_data(DemoTeam.demo?(team), status) |> Jason.encode!(),
      "photo.png" => LoadImage.photo(member, :square),
      "logo.png" => LoadImage.logo(team, :square),
      "qr.svg" =>
        card.code |> MemberCard.qr_url(Web.VerifyHost.url()) |> EQRCode.encode() |> EQRCode.svg()
    }

    case side do
      :print -> side |> source() |> Typst.compile(files)
      :image -> side |> source() |> Typst.compile(files, png: @ppi)
    end
  end

  @doc """
  Pure. What the drawing writes, as the card.json the template reads. `card` has
  `member: [team: :organization]`; `sample?` marks a Try a demo card, as its passes are
  marked (#857); `status` is its `MemberCard.link_status/2`.
  """
  def card_data(%MemberCard{member: member} = card, sample?, status \\ :active) do
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
      state: state(status),
      notes: [
        ["How to verify this card", MemberCard.how_to_check(code)],
        ["Issued by", MemberCard.issuer(team)]
      ],
      sheet_title: "#{team.name} ID card · #{member.name}",
      sheet_help: @help
    }
  end

  defp source(:print), do: ~s|#import "card.typ": *\n#sheet(json("card.json"))\n|

  # No page fill, so the corners outside the card's rounding stay see-through on a dark page.
  defp source(:image),
    do:
      ~s|#import "card.typ": *\n#set page(width: auto, height: auto, margin: 0pt, fill: none)\n| <>
        ~s|#pass(json("card.json"))\n|

  # What a dead card's picture says where its QR code goes.
  defp state(:active), do: nil
  defp state(:replaced), do: "Replaced"
  defp state(:cancelled), do: "Cancelled"
  defp state(:inactive), do: "Not active"

  defp template, do: Application.app_dir(:sarduty, "priv/typst/member_card.typ")
end
