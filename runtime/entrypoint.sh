#!/usr/bin/env bash
set -euo pipefail

if [[ -z ${TUNNEL_TOKEN:-} ]]; then
  echo 'TUNNEL_TOKEN is required to start Cloudflare Tunnel.' >&2
  exit 64
fi

mkdir -p "$DSH_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

args=(web --host 127.0.0.1 --port 3080 --no-open)
if [[ -n ${DSH_PUBLIC_URL:-} ]]; then
  authority=$(node -e 'process.stdout.write(new URL(process.env.DSH_PUBLIC_URL).host)')
  args+=(--public-url "$DSH_PUBLIC_URL" --trusted-host "$authority")
fi

children=()
stop_children() {
  trap - TERM INT
  if ((${#children[@]})); then
    kill -TERM "${children[@]}" 2>/dev/null || true
    wait "${children[@]}" 2>/dev/null || true
  fi
}
trap 'stop_children; exit 143' TERM
trap 'stop_children; exit 130' INT

# Only the connector needs the tunnel credential.
env -u TUNNEL_TOKEN dsh "${args[@]}" &
children+=("$!")
cloudflared --no-autoupdate tunnel run &
children+=("$!")

status=0
wait -n "${children[@]}" || status=$?
stop_children
# Both services are required, including when one exits without an error.
if ((status == 0)); then status=1; fi
exit "$status"
