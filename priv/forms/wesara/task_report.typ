// WESARA's Task report, drawn blank (#963): the page task_report.txt prints on, for a
// made-up organization, so a demo and the dev teams try forms and Publish without an
// agency's custom fields. Page 1 is letter paper, page 2 legal. Draw it again after a
// change, then read task_report.txt's places, which sit on these lines:
//
//   mise exec -- mix run --no-start tools/forms/draw_page.exs priv/forms/wesara/task_report.typ
//
// Every position is in points from the page's top left, as the form's places are.
#set document(title: "Task report", date: none)
#set text(font: "Arimo", size: 9pt, fill: rgb("#1f3a5f"))
#let at(x, y, body) = place(top + left, dx: x * 1pt, dy: y * 1pt, body)
#let rule(x1, x2, y) = at(x1, y, line(length: (x2 - x1) * 1pt, stroke: 0.5pt + rgb("#1f3a5f")))
#let box9(x, y) = at(x, y, rect(width: 9pt, height: 9pt, stroke: 0.5pt + rgb("#1f3a5f")))

#set page(width: 612pt, height: 792pt, margin: 0pt)
#at(72, 54, text(size: 16pt, weight: "bold")[Western Search and Rescue Association · Task report])
#at(72, 76)[Made up, for trying SAR Duty. Page 1 of 2.]

#at(72, 112)[Task number]
#rule(160, 300, 122)
#at(320, 112)[Task name]
#rule(400, 500, 122)

#at(72, 142)[Date of task]
#rule(160, 300, 152)

#at(72, 172)[Task type]
#box9(160, 170)
#at(174, 172)[Search]
#box9(240, 170)
#at(254, 172)[Rescue]
#box9(320, 170)
#at(334, 172)[Evidence search]

#at(72, 202)[People helped]
#rule(160, 220, 212)
#at(240, 202)[Injured]
#rule(290, 340, 212)

#at(72, 234)[Description]
#for y in (258, 276, 294, 312) { rule(72, 540, y) }

#at(72, 342)[Task leader]
#rule(160, 400, 352)
#at(72, 374)[Signature]
#rule(160, 400, 384)

#pagebreak()
#set page(width: 612pt, height: 1008pt, margin: 0pt)
#at(72, 54, text(size: 16pt, weight: "bold")[Attachments])
#at(72, 76)[Page 2 of 2, on legal paper.]
#at(72, 112)[ERR attached]
#box9(160, 110)
#at(72, 900)[Prepared by]
#rule(330, 540, 936)
