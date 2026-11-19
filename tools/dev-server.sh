#!/usr/bin/env bash
# Serves this checkout, a worktree or the main one, as the one dev server: port 4025, on
# the main checkout's dev database, with watchers and live reload. Stop any other server
# on 4025 first.
#
#   tools/dev-server.sh            # in the foreground
#   tools/dev-server.sh --detach   # in the background, log in tmp/dev-server.log
#
# It prints the URL to open. DEV_URL_HOST in .mise.local.toml is the host in that URL, QR
# codes, and emailed links, such as one a phone can reach; http://localhost:4025 without it.
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

  if host = System.get_env("DEV_URL_HOST") do
    endpoint = Application.get_env(:sarduty, Web.Endpoint)
    url = [host: host, scheme: "https", port: 443]
    Application.put_env(:sarduty, Web.Endpoint, Keyword.put(endpoint, :url, url))
  end

  Application.put_env(:phoenix, :serve_endpoints, true)
  {:ok, _} = Application.ensure_all_started(:sarduty)
')

host=$(mise exec -- printenv DEV_URL_HOST || true)
url=${host:+https://$host}
url=${url:-http://localhost:4025}

if [ "${1:-}" = "--detach" ]; then
  mkdir -p tmp
  nohup "${serve[@]}" > tmp/dev-server.log 2>&1 < /dev/null &
  echo "Serving $url on 4025, pid $!, log tmp/dev-server.log"
else
  echo "Serving $url on 4025"
  exec "${serve[@]}"
fi
