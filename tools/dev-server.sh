#!/usr/bin/env bash
# Serves this checkout, a worktree or the main one, as the one dev server: port 4025,
# https://sarduty.test and https://sarduty.gshaw.ca, on the main checkout's dev database,
# with watchers and live reload. Stop any other server on 4025 first.
#
#   tools/dev-server.sh            # in the foreground
#   tools/dev-server.sh --detach   # in the background, log in tmp/dev-server.log
#
# Dev SAR (tools/dev-sar.exs) is the team to try things on.
set -euo pipefail
cd "$(dirname "$0")/.."

main=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
export DEV_DB="$main/db/sarduty_dev.db"
[ -e .mise.local.toml ] || cp "$main/.mise.local.toml" .
[ -d priv/static/assets ] || mise exec -- mix assets.setup

if lsof -nP -iTCP:4025 -sTCP:LISTEN >/dev/null; then
  echo "Something already serves 4025. Stop it first." >&2
  exit 1
fi

serve=(mise exec -- mix run --no-halt --no-start -e '
  repo = Application.get_env(:sarduty, App.Repo)
  Application.put_env(:sarduty, App.Repo, Keyword.put(repo, :database, System.fetch_env!("DEV_DB")))
  Application.put_env(:phoenix, :serve_endpoints, true)
  {:ok, _} = Application.ensure_all_started(:sarduty)
')

if [ "${1:-}" = "--detach" ]; then
  mkdir -p tmp
  nohup "${serve[@]}" > tmp/dev-server.log 2>&1 < /dev/null &
  echo "Serving on 4025, pid $!, log tmp/dev-server.log"
else
  exec "${serve[@]}"
fi
