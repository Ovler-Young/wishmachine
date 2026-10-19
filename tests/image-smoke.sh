#!/usr/bin/env bash
set -euo pipefail

image=${1:?Usage: image-smoke.sh IMAGE}

# Keep the real Harness process isolated; Tunnel requires a live credential.
container=$(docker run --detach --network none --entrypoint /bin/dsh "$image" \
  web --host 127.0.0.1 --port 3080 --no-open)
trap 'docker rm -f "$container" > /dev/null' EXIT

for ((attempt = 0; attempt < 90; attempt++)); do
  if [[ $(docker inspect --format '{{.State.Running}}' "$container") != true ]]; then
    echo 'Harness exited before its HTTP server became ready.' >&2
    exit 1
  fi
  status=$(docker exec "$container" curl --silent --max-time 2 --output /dev/null \
    --write-out '%{http_code}' http://127.0.0.1:3080/ || true)
  if [[ "$status" == 401 ]]; then
    echo 'Packaged Harness is ready and requires authentication.'
    exit 0
  fi
  sleep 1
done

# Startup output contains the Harness authentication URL and stays private.
printf 'Harness did not return HTTP 401 within 90 attempts; last status: %s\n' "$status" >&2
exit 1
