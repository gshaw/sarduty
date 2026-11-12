// EMCR's Expense reimbursement request supplement, drawn blank in D4H's layout (#950):
// the page supplement.txt prints on, with room for 18 people. EMCR takes D4H's drawn
// page today, so it takes this one. Draw it again after a change, then read the diff of
// supplement.txt's places, which sit on these lines:
//
//   mise exec -- mix run --no-start tools/forms/draw_page.exs priv/forms/bcsara/supplement.typ
//
// Every position is in points from the page's top left, as the form's places are.
#set document(title: "Expense reimbursement request supplement", date: none)
#set page(width: 612pt, height: 792pt, margin: 0pt)
#set text(font: "Arimo", size: 8.5pt)

#let at(x, y, body) = place(top + left, dx: x * 1pt, dy: y * 1pt, body)
// A line across the page from x1 to x2, and one down it from y1 to y2.
#let across(x1, x2, y, w: 0.6pt) = at(x1, y, line(length: (x2 - x1) * 1pt, stroke: w))
#let down(x, y1, y2) = at(x, y1, line(angle: 90deg, length: (y2 - y1) * 1pt, stroke: 0.6pt))
// A label whose baseline sits at y.
#let label(x, y, body, weight: "bold") = at(x, y - 6.5, text(weight: weight, body))
// Text centred between x1 and x2, its baseline at y.
#let centred(x1, x2, y, body) = at(x1, y - 6.5, box(width: (x2 - x1) * 1pt, align(center, text(weight: "bold", body))))
#let shaded(x1, x2, y1, y2) = at(x1, y1, rect(width: (x2 - x1) * 1pt, height: (y2 - y1) * 1pt, fill: rgb("#f2f2f2"), stroke: none))

// The table's edges, its columns' edges, and its rows.
#let left-edge = 40
#let right-edge = 572
#let cols = (40, 341.6, 374.4, 410.4, 461.4, 521.6, 572)
#let top-edge = 116
#let heading-bottom = 129.6
#let travel-split = 144
#let header-bottom = 165.6
#let row-height = 14
#let rows = 18
#let rows-bottom = header-bottom + rows * row-height
#let note-bottom = rows-bottom + 14
#let subtotal-bottom = note-bottom + 16

// The agency, where D4H puts its logo, and the form's name.
#at(left-edge, 38, text(size: 6.5pt, tracking: 0.5pt)[BRITISH COLUMBIA])
#at(left-edge, 47, text(size: 9pt)[Emergency Management and Climate Readiness])
#at(232, 35, box(width: 340pt, align(right, text(size: 12pt, weight: "bold")[EXPENSE REIMBURSEMENT REQUEST SUPPLEMENT])))

// The task, and when its expenses were incurred.
#label(left-edge, 98)[Task No:]
#across(78, 221, 99.5)
#label(232, 98)[Incurred (from)]
#across(295, 397, 99.5)
#label(407, 98)[(to)]
#across(426, right-edge, 99.5)

// The table's heading and its column heads, shaded as D4H's are.
#shaded(left-edge, right-edge, top-edge, header-bottom)
#centred(left-edge, right-edge, top-edge + 10)[PERSONAL/VOLUNTEER/LOCAL GOV/SOCIETY EXPENSES]
#centred(cols.at(0), cols.at(1), 151)[To Whom Paid]
#centred(cols.at(1), cols.at(3), heading-bottom + 10)[Travel]
#centred(cols.at(1), cols.at(2), travel-split + 13)[km]
#centred(cols.at(2), cols.at(3), travel-split + 13)[rate#super[2]]
#centred(cols.at(3), cols.at(4), 151)[Meals#super[1]]
#centred(cols.at(4), cols.at(5), heading-bottom + 10.5)[Personal]
#centred(cols.at(4), cols.at(5), heading-bottom + 21.5)[Equipment]
#centred(cols.at(4), cols.at(5), heading-bottom + 32.5)[Allowance]
#centred(cols.at(5), cols.at(6), 151)[Total]

// The table's lines: its box, the heading's, each column's, and each row's.
#across(left-edge, right-edge, top-edge)
#across(left-edge, right-edge, heading-bottom)
#across(cols.at(1), cols.at(3), travel-split)
#for i in range(rows + 1) {
  across(left-edge, right-edge, header-bottom + i * row-height)
}
#across(left-edge, right-edge, note-bottom)
#across(left-edge, right-edge, subtotal-bottom)
#down(left-edge, top-edge, subtotal-bottom)
#down(right-edge, top-edge, subtotal-bottom)
#for x in (cols.at(1), cols.at(3), cols.at(4), cols.at(5)) {
  down(x, heading-bottom, rows-bottom)
}
#down(cols.at(2), travel-split, rows-bottom)
#down(cols.at(5), note-bottom, subtotal-bottom)

// The notes on Meals and rate, and the subtotal.
#at(left-edge + 4, rows-bottom + 4.5, text(size: 6.5pt)[1. Calculated to a maximum of 4 per 24 hour period.#h(8pt)2. Rates as per current 5.06 Volunteer Reimbursement and Allowance Rate Chart.])
#at(cols.at(4), note-bottom + 4.5, box(width: (cols.at(5) - cols.at(4) - 6) * 1pt, align(right, text(weight: "bold")[SUBTOTAL])))

// The task leader certifies it, and signs.
#at(left-edge, subtotal-bottom + 26, text(style: "italic")[I certify that the people listed above attended this task:])
#label(left-edge, subtotal-bottom + 64)[Task Leader:]
#across(114, 297, subtotal-bottom + 65.5)
#label(316, subtotal-bottom + 64)[Signature:]
#across(361, right-edge, subtotal-bottom + 65.5)
#label(left-edge, subtotal-bottom + 86)[Date:]
#across(66, 297, subtotal-bottom + 87.5)
#label(316, subtotal-bottom + 86)[Page:]
#across(343, right-edge, subtotal-bottom + 87.5)
