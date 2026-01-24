---
name: External Adapter (Req)
description: Add or extend external service adapters using Req, consistent error handling, and config.
---

## Scope

Use this skill for new integrations like D4H or Mapbox.

## Checklist

- Add adapter modules under `lib/app/adapter` and keep parsing logic in dedicated submodules if needed.
- Use `Req.new/1` to build a context (base URL, headers, auth) and `Req.get!/post!/patch!` for calls.
- Return `{:ok, value}` or `{:error, reason}` consistently; avoid throwing in callers.
- Read secrets and host config from `config/*.exs` or `runtime.exs`.
- Never use other HTTP clients (`:httpoison`, `:tesla`, `:httpc`).
