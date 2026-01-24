---
name: UI Components
description: Build and compose reusable UI components in Phoenix HEEx with Tailwind CSS.
---

## Scope

Use this skill when adding or updating UI components or shared UI patterns.

## Checklist

- Add reusable components in `lib/web/components` (prefer `core.ex` and `ui.ex`).
- Use `~H` templates, `attr`/`slot` declarations, and keep assigns explicit.
- Use `<.icon>` for icons and `<.input>` for form fields.
- Keep layout-only concerns in `Web.Layouts` (flash group stays there).
- Use Tailwind utility classes; avoid `@apply` and avoid external UI kits.
- Provide accessible markup (labels, aria attributes, focus states).
- Add unique DOM IDs for key elements used in tests.
