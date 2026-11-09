// An ID card's two sides, drawn once for the card page's pictures, Save image, and the
// printed card (App.Operation.DrawMemberCard, #973). Both sides are 54 mm wide, a badge
// holder's width. The front is always one size; the back is as tall as its list.
//
// `card` is the dictionary DrawMemberCard writes as card.json. `ink` draws black on
// white, for printing; otherwise the pass's navy and yellow.

#let navy = rgb(28, 45, 66)
#let yellow = rgb(255, 196, 0)

#let colours(ink) = if ink {
  (fill: white, text: black, label: black, quiet: black, rule: black)
} else {
  (fill: navy, text: white, label: yellow, quiet: rgb(255, 255, 255, 190), rule: rgb(255, 255, 255, 36))
}

#let caps(c, body) = text(size: 4.6pt, weight: "bold", fill: c.label, upper(body))

#let side(c, ink, body) = block(
  width: 54mm,
  fill: c.fill,
  stroke: if ink { 0.6pt + black } else { none },
  inset: (x: 2.6mm, top: 2.3mm, bottom: 2.6mm),
  spacing: 0pt,
  {
    set text(font: "Arimo", size: 6.2pt, fill: c.text)
    set par(leading: 0.42em, spacing: 0.42em)
    body
  },
)

#let header(c, card, right: none) = grid(
  columns: (4.6mm, 1fr, auto),
  column-gutter: 1.4mm,
  align: horizon,
  box(clip: true, radius: 0.9mm, image("logo.png", width: 4.6mm)),
  text(size: 7.2pt, weight: "bold", card.team),
  if right != none { text(size: 5.6pt, fill: c.quiet, right) },
)

#let front(card, ink: false) = {
  let c = colours(ink)
  side(c, ink, {
    header(c, card)
    v(2.4mm)
    grid(
      columns: (1fr, 12.2mm),
      column-gutter: 2mm,
      [#caps(c, card.name_label) \ #text(size: 10.4pt, card.name)],
      box(clip: true, radius: 1.2mm, stroke: if ink { 0.5pt + black } else { none },
        image("photo.png", width: 12.2mm, height: 12.2mm, fit: "cover")),
    )
    v(2mm)
    grid(
      columns: (auto, auto),
      column-gutter: 3mm,
      [#caps(c, "Status") \ #card.status],
      if card.member_since != none [#caps(c, "Member since") \ #card.member_since],
    )
    v(2.6mm)
    align(center, box(
      fill: white,
      radius: if ink { 0pt } else { 1.2mm },
      inset: if ink { (bottom: 0.6mm) } else { (x: 1.3mm, top: 1.3mm, bottom: 0.8mm) },
      {
        image("qr.svg", width: 19.6mm)
        v(0.5mm)
        text(size: 5.8pt, weight: "bold", fill: black, card.code)
      },
    ))
    v(1.9mm)
    align(center, text(size: 5.2pt, fill: c.quiet, card.made))
  })
}

#let back(card, ink: false) = {
  let c = colours(ink)
  side(c, ink, {
    header(c, card, right: card.name)
    v(2.4mm)
    caps(c, "Endorsements")
    v(0.6mm)
    if card.endorsements.len() == 0 {
      text(fill: c.quiet, "None")
    } else {
      for (i, e) in card.endorsements.enumerate() {
        if i > 0 { line(length: 100%, stroke: 0.4pt + c.rule) }
        block(above: 1.1mm, below: 1.1mm, grid(
          columns: (1fr, auto),
          column-gutter: 2mm,
          e.name, text(fill: c.quiet, e.expires),
        ))
      }
    }
    for (title, body) in card.notes {
      v(2.2mm)
      caps(c, title)
      v(0.4mm)
      body
    }
  })
}

// One Letter page to cut out: whose card, what to do, and both sides at actual size,
// each in a dashed cut line 2 mm out so a crooked cut misses the card.
#let sheet(card, ink: true) = {
  set document(title: card.sheet_title)
  set page(paper: "us-letter", margin: 0.5in)
  set text(font: "Arimo", size: 9pt)
  text(size: 12pt, weight: "bold", card.sheet_title)
  v(1mm)
  card.sheet_help
  v(5mm)
  let cut(name, body) = stack(
    spacing: 1.5mm,
    text(size: 7pt, fill: rgb(80, 80, 80), name),
    block(stroke: (paint: rgb(120, 120, 120), thickness: 0.4pt, dash: "dashed"), inset: 2mm, body),
  )
  grid(
    columns: (auto, auto),
    column-gutter: 10mm,
    align: top,
    cut("Front", front(card, ink: ink)),
    cut("Back", back(card, ink: ink)),
  )
}
