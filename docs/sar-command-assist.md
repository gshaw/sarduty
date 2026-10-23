# SAR Command Assist

SAR Command Assist (SCA, [sarassist.ca](https://www.sarassist.ca)) is the incident tool
many BC teams run at callouts. It is free, distributed by BCSARA, and written by Dylan
Baker, a Campbell River SAR manager. SAR Duty doesn't call it and it doesn't call SAR
Duty; both read the same D4H. Notes from its site and our issues, 2026-10-22.

## What it does

- **ICS paperwork.** Typed once, filled in everywhere: ICS 202, 204, 211, 215, 309, and a
  whole Incident Action Plan as one PDF.
- **Windows desktop app.** Shares over a local network with no internet, or remotely
  through its Internet Sync.
- **My SAR Assist**, a phone app (iOS and Android, needs internet). A member enters their
  name, emergency contact, and qualifications, and gets a QR code. The command computer
  scans it to sign them in and out (the ICS 211 check-in list), with a live in/out board.
  The code carries the profile itself, so it works for mutual aid members SCA has never
  seen. It matches a known member by email or EMCR ID.

## D4H sync

From [its D4H Sync page](https://www.sarassist.ca/Support/D4HSync), SCA 7.13 or later:

- Pulls **personnel and qualifications** from one D4H team, each time SCA opens online
  and on demand. D4H qualifications map to SCA qualifications, several to one.
- Emergency contacts come too when the key has Member+ permission. The suggested key is
  a dedicated "SCA Sync" user with Member+, Draft Incidents, and Equipment Basic.
- **No groups.** So SCA can't see what SAR Duty's [group rules](group-rules.md) decide,
  such as who is an active SARM rather than anyone who once took the course. Brad Parker
  asked about this on 2026-10-22.

Sign-out times and kilometres feed the D4H entry for the incident. Since SCA covers
incident attendance, SAR Duty removed its attendance import (#212, #424); attendance at
the door ([attendance-at-the-door.md](attendance-at-the-door.md)) is for trainings.

## Where they meet

- **ID card QR codes** (#299): sign a member into SCA with their SAR Duty card. The verify
  endpoint could return the D4H member ID, never contact details or emergency contacts.
  Open.
- **Group membership** (above): SAR Duty writes it to D4H, so SCA reading D4H groups is
  the clean way to get it there.
