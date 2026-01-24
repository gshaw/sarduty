---
name: LiveView Feature
description: Add a new LiveView UI feature following the project's layout, routing, and testing patterns.
---

## Scope

Use this skill when adding new pages, flows, or interactions in LiveView.

## Checklist

- Create a LiveView under `lib/web/live` and pick the correct layout macro:
  - `use Web, :live_view_app_layout` (authenticated app pages)
  - `use Web, :live_view_narrow_layout` (narrow forms/settings)
  - `use Web, :live_view_marketing_layout` (public/marketing)
- Keep render templates focused on page content; layout handles nav + flash (`<.flash_group>` stays in `Web.Layouts`).
- Add routes in `lib/web/router.ex` under the proper `live_session` and `scope`, using `on_mount` from `Web.UserAuth`.
- Use `~p` for routes and `<.link navigate>` / `<.link patch>` with `push_navigate` / `push_patch`.
- Forms: build changesets or params, assign with `to_form`, use `<.form id="...">` and `<.input field={@form[:field]}>`.
- Lists: use LiveView streams with `phx-update="stream"` and `@streams`.
- Add LiveView tests in `test/sartask_web/live` using `Phoenix.LiveViewTest`, targeting the element IDs you added.
