#!/bin/sh
set -eu

conf=/etc/nats/nats-server.conf
missing=0
for var in $(grep -o '\$[A-Z0-9_]*_NATS_PASSWORD' "$conf" | tr -d '$' | sort -u); do
  eval "val=\${$var-}"
  if [ "${#val}" -lt 16 ]; then
    echo "refusing to start: $var must be set to at least 16 characters" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

exec docker-entrypoint.sh "$@"
