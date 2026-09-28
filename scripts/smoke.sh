#!/usr/bin/env bash
set -euo pipefail

engine="${ENGINE:-docker}"
image="${IMAGE:-altalune-nats:smoke}"
token="smoke-$RANDOM$RANDOM$RANDOM"
name="altalune-nats-smoke-$$"

cleanup() { "$engine" rm -f "$name" "$name-notoken" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; "$engine" logs "$name" 2>&1 | tail -20 >&2 || true; exit 1; }

"$engine" build -q -t "$image" . >/dev/null

echo "==> refuses to start without NATS_TOKEN"
"$engine" run -d --name "$name-notoken" "$image" >/dev/null
for _ in $(seq 1 20); do
  [ "$("$engine" inspect -f '{{.State.Running}}' "$name-notoken")" = "false" ] && break
  sleep 0.5
done
[ "$("$engine" inspect -f '{{.State.Running}}' "$name-notoken")" = "false" ] || fail "started without NATS_TOKEN"
[ "$("$engine" inspect -f '{{.State.ExitCode}}' "$name-notoken")" != "0" ] || fail "exited 0 without NATS_TOKEN"

echo "==> starts with JetStream on /data"
"$engine" run -d --name "$name" -e NATS_TOKEN="$token" \
  -p 127.0.0.1::4222 -p 127.0.0.1::8222 "$image" >/dev/null
client_port="$("$engine" port "$name" 4222/tcp | head -1 | awk -F: '{print $NF}')"
http_port="$("$engine" port "$name" 8222/tcp | head -1 | awk -F: '{print $NF}')"

for _ in $(seq 1 40); do
  curl -fsS "http://127.0.0.1:$http_port/healthz?js-enabled-only=true" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -fsS "http://127.0.0.1:$http_port/healthz?js-enabled-only=true" >/dev/null || fail "healthz with JetStream"
curl -fsS "http://127.0.0.1:$http_port/jsz" | grep -q '"store_dir": *"/data' || fail "store_dir is not /data"

nats_ping() {
  local connect="$1" reply
  exec 3<>"/dev/tcp/127.0.0.1/$client_port"
  read -r -t 5 _ <&3
  printf 'CONNECT %s\r\nPING\r\n' "$connect" >&3
  read -r -t 5 reply <&3 || reply=""
  exec 3<&- 3>&-
  printf '%s' "$reply"
}

echo "==> rejects a client without the token"
nats_ping '{"verbose":false}' | grep -q 'Authorization Violation' || fail "unauthenticated client accepted"

echo "==> rejects a wrong token"
nats_ping '{"verbose":false,"auth_token":"wrong"}' | grep -q 'Authorization Violation' || fail "wrong token accepted"

echo "==> accepts the token"
nats_ping "{\"verbose\":false,\"auth_token\":\"$token\"}" | grep -q 'PONG' || fail "token rejected"

echo "OK"
