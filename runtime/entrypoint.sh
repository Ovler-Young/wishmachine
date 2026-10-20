#!/usr/bin/env bash
set -euo pipefail

if [[ -z ${TUNNEL_TOKEN:-} ]]; then
  echo 'TUNNEL_TOKEN is required to start Cloudflare Tunnel.' >&2
  exit 64
fi

mkdir -p "$DSH_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

ssh_enabled=false
case "${WISHMACHINE_SSH_ENABLED:-false}" in
  true | 1 | yes)
    ssh_enabled=true
    if [[ ! -s /run/configs/wishmachine_ssh_authorized_keys ]]; then
      echo 'SSH requires a nonempty /run/configs/wishmachine_ssh_authorized_keys file.' >&2
      exit 64
    fi
    ssh_directory="$XDG_DATA_HOME/wishmachine/ssh"
    install -d -m 700 "$ssh_directory"
    install -m 600 /run/configs/wishmachine_ssh_authorized_keys "$ssh_directory/authorized_keys"
    host_key="$ssh_directory/ssh_host_ed25519_key"
    if [[ ! -e "$host_key" ]]; then
      ssh-keygen -q -t ed25519 -N '' -f "$host_key"
    fi
    ;;
  false | 0 | no | "") ;;
  *)
    echo 'WISHMACHINE_SSH_ENABLED must be true, 1, yes, false, 0, or no.' >&2
    exit 64
    ;;
esac

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
if [[ "$ssh_enabled" == true ]]; then
  env -u TUNNEL_TOKEN /bin/sshd -D -e -f /etc/wishmachine-sshd_config -h "$host_key" \
    -o "AuthorizedKeysFile=$ssh_directory/authorized_keys" &
  children+=("$!")
fi
cloudflared --no-autoupdate tunnel run &
children+=("$!")

status=0
wait -n "${children[@]}" || status=$?
stop_children
# Every enabled service is required, including when one exits without an error.
if ((status == 0)); then status=1; fi
exit "$status"
