// An ID card, drawn by App.Operation.DrawMemberCard: `pass`, the card page's picture that
// Save image saves, like the Wallet pass; and `sheet`, Print ID card's Letter page, with
// both sides at CR80 size, 85.60 × 53.98 mm with 3.18 mm corners, the size of a plastic ID
// card, so a printed copy fits any card holder. The printed sides are white under a line
// of SAR Duty's navy, the Wallet passes' colour, so any team logo shows and any printer
// prints them.
//
// `card` is the dictionary DrawMemberCard writes as card.json.

#let navy = rgb(28, 45, 66)
#let ink = rgb(17, 24, 39)
#let quiet = rgb(75, 85, 99)
#let hairline = rgb(200, 205, 212)
#let card-w = 85.60mm
#let card-h = 53.98mm
#let card-r = 3.18mm

#let label(body) = text(size: 4.8pt, weight: "bold", fill: navy, upper(body))

// The card's outline: the cut line on the Letter page, and a hairline on screen so a white
// card shows on a white page.
#let side(edge, body) = block(
  width: card-w,
  height: card-h,
  fill: white,
  radius: card-r,
  clip: true,
  stroke: if edge != none { edge } else { 0.3pt + hairline },
  inset: (x: 3mm, top: 2.4mm, bottom: 2.6mm),
  spacing: 0pt,
  {
    set text(font: "Arimo", size: 6.4pt, fill: ink)
    set par(leading: 0.42em, spacing: 0.5em)
    // "SAR Duty" never breaks, so "Duty." never sits alone.
    show "SAR Duty": box
    body
  },
)

// Both sides' top: the team's logo, its name in all the width left, and the navy line.
// A long name drops from 8 pt to 6.6 pt, and wraps only if it still doesn't fit.
#let card-top(card) = {
  block(height: 6.4mm, spacing: 0pt, align(horizon, grid(
    columns: (auto, 1fr),
    column-gutter: 2mm,
    align: horizon,
    image("logo.png", height: 6.4mm),
    layout(size => {
      let one = text(size: 8pt, weight: "bold", fill: navy, card.team)
      if measure(one).width <= size.width { one } else {
        block(text(size: 6.6pt, weight: "bold", fill: navy, card.team))
      }
    }),
  )))
  v(1.6mm)
  block(width: 100%, height: 1mm, fill: navy, spacing: 0pt)
}

// The code as a person types it, in IBM Plex Mono, the app's font for codes.
#let code-text(code, size) = text(font: "IBM Plex Mono", weight: "medium", size: size, fill: black, code)

#let code(card, width, size) = align(center, {
  image("qr.svg", width: width)
  v(0.4mm)
  code-text(card.code, size)
})

#let front(card, edge: none) = side(edge, {
  card-top(card)
  v(1fr)
  grid(
    columns: (24mm, 1fr, 22mm),
    column-gutter: 3mm,
    align: top,
    box(clip: true, radius: 1mm, stroke: 0.4pt + hairline,
      image("photo.png", width: 24mm, height: 24mm, fit: "cover")),
    {
      if card.name_label != none { label(card.name_label); linebreak() }
      text(size: 11pt, weight: "bold", card.name)
      if card.member_since != none {
        linebreak()
        text(size: 6.8pt, fill: quiet, [Member since #card.member_since])
      }
      v(3.2mm)
      label("Issued")
      linebreak()
      text(size: 7pt, card.issued)
    },
    code(card, 22mm, 6.2pt),
  )
  v(1fr)
})

// What the Wallet passes' backs say about verifying and who issued the card, beside the
// code again, so either side verifies.
#let back(card, edge: none) = side(edge, {
  card-top(card)
  v(1fr)
  grid(
    columns: (20mm, 1fr),
    column-gutter: 3.4mm,
    align: top,
    code(card, 20mm, 5.8pt),
    {
      text(size: 9pt, weight: "bold", card.name)
      v(2.2mm)
      for (i, (title, body)) in card.notes.enumerate() {
        if i > 0 { v(2mm) }
        label(title)
        v(0.3mm)
        text(size: 6.2pt, body)
      }
    },
  )
  v(1fr)
})

// The card page's picture, which Save image saves: the front as the iPhone Wallet pass
// draws it, upright in SAR Duty's navy with yellow labels, so a member can show the page
// or the picture as they would the pass. Issued takes the pass's Status, and there is no
// Valid until: a saved picture never updates.
#let yellow = rgb(255, 196, 0)
#let pass-label(body) = text(size: 5.4pt, weight: "bold", fill: yellow, upper(body))
#let pass-field(name, value) = [#pass-label(name) \ #text(size: 9pt, value)]

#let pass(card) = block(
  width: 54mm,
  height: 74mm,
  fill: navy,
  radius: 3mm,
  clip: true,
  inset: (x: 3mm, top: 2.4mm, bottom: 2.2mm),
  spacing: 0pt,
  {
    set text(font: "Arimo", size: 6.4pt, fill: white)
    set par(leading: 0.42em, spacing: 0.5em)
    // The logo, and the team's name in the width left: 9 pt, 7.4 pt if that doesn't fit
    // on one line, then wrapped.
    grid(
      columns: (7.4mm, 1fr),
      column-gutter: 2mm,
      align: horizon,
      image("logo.png", height: 7.4mm),
      layout(size => {
        let one = text(size: 9pt, weight: "bold", fill: yellow, card.team)
        if measure(one).width <= size.width { one } else {
          block(text(size: 7.4pt, weight: "bold", fill: yellow, card.team))
        }
      }),
    )
    v(3mm)
    grid(
      columns: (1fr, 12.5mm),
      column-gutter: 2mm,
      align: top,
      {
        pass-label(if card.name_label != none { card.name_label } else { "Member" })
        linebreak()
        text(size: 12pt, card.name)
      },
      image("photo.png", width: 12.5mm, height: 12.5mm, fit: "cover"),
    )
    v(2.6mm)
    grid(
      columns: (1fr, 1fr),
      column-gutter: 2mm,
      pass-field("Issued", card.issued),
      ..if card.member_since != none { (pass-field("Member since", card.member_since),) },
    )
    v(1fr)
    align(center, box(fill: white, radius: 1mm, inset: (x: 1.6mm, top: 1.6mm, bottom: 1.1mm), {
      image("qr.svg", width: 20.5mm)
      v(0.6mm)
      code-text(card.code, 7pt)
    }))
  },
)

// One Letter page to cut out: whose card, what to do, and both sides at actual size, each
// cut on its own edge, so the piece is the card's size and fits a card holder.
#let sheet(card) = {
  set document(title: card.sheet_title)
  set page(paper: "us-letter", margin: 0.5in)
  set text(font: "Arimo", size: 9pt)
  text(size: 12pt, weight: "bold", card.sheet_title)
  v(1mm)
  card.sheet_help
  v(5mm)
  let edge = (paint: rgb(120, 120, 120), thickness: 0.4pt, dash: "dashed")
  let cut(name, body) = stack(spacing: 1.5mm, text(size: 7pt, fill: rgb(80, 80, 80), name), body)
  grid(
    columns: (auto, auto),
    column-gutter: 8mm,
    align: top,
    cut("Front", front(card, edge: edge)),
    cut("Back", back(card, edge: edge)),
  )
}
