#!/usr/bin/env bash
set -euo pipefail

engine="${ENGINE:-docker}"
image="${IMAGE:-altalune-nats:smoke}"
name="altalune-nats-smoke-$$"
users=(altempl openwa yasaku)

seed="$RANDOM$RANDOM$RANDOM$RANDOM"
pw() { printf 'smoke-%s-%s' "$1" "$seed"; }
env_args=()
for u in "${users[@]}"; do
  env_args+=(-e "$(printf '%s' "$u" | tr '[:lower:]' '[:upper:]')_NATS_PASSWORD=$(pw "$u")")
done

cleanup() { "$engine" rm -f "$name" "$name-nopw" "$name-emptypw" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; "$engine" logs "$name" 2>&1 | tail -20 >&2 || true; exit 1; }

refuses_to_start() {
  local ctr="$1"; shift
  "$engine" run -d --name "$ctr" "$@" "$image" >/dev/null
  for _ in $(seq 1 20); do
    [ "$("$engine" inspect -f '{{.State.Running}}' "$ctr")" = "false" ] && break
    sleep 0.5
  done
  [ "$("$engine" inspect -f '{{.State.Running}}' "$ctr")" = "false" ] || return 1
  [ "$("$engine" inspect -f '{{.State.ExitCode}}' "$ctr")" != "0" ]
}

"$engine" build -q -t "$image" . >/dev/null

echo "==> refuses to start without the account passwords"
refuses_to_start "$name-nopw" || fail "started without passwords"

echo "==> refuses to start with an empty account password"
refuses_to_start "$name-emptypw" "${env_args[@]}" -e OPENWA_NATS_PASSWORD= || fail "started with an empty password"

echo "==> starts with JetStream on /data"
"$engine" run -d --name "$name" "${env_args[@]}" \
  -p 127.0.0.1::4222 -p 127.0.0.1::8222 "$image" >/dev/null
client_port="$("$engine" port "$name" 4222/tcp | head -1 | awk -F: '{print $NF}')"
http_port="$("$engine" port "$name" 8222/tcp | head -1 | awk -F: '{print $NF}')"

for _ in $(seq 1 40); do
  curl -fsS "http://127.0.0.1:$http_port/healthz?js-enabled-only=true" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -fsS "http://127.0.0.1:$http_port/healthz?js-enabled-only=true" >/dev/null || fail "healthz with JetStream"
curl -fsS "http://127.0.0.1:$http_port/jsz" | grep -q '"store_dir": *"/data' || fail "store_dir is not /data"

connect_json() { printf '{"verbose":false,"user":"%s","pass":"%s"}' "$1" "$2"; }

nats_ping() {
  local connect="$1" reply
  exec 3<>"/dev/tcp/127.0.0.1/$client_port"
  read -r -t 5 _ <&3
  printf 'CONNECT %s\r\nPING\r\n' "$connect" >&3
  read -r -t 5 reply <&3 || reply=""
  exec 3<&- 3>&-
  printf '%s' "$reply"
}

echo "==> rejects a client without credentials"
nats_ping '{"verbose":false}' | grep -q 'Authorization Violation' || fail "unauthenticated client accepted"

echo "==> rejects a wrong password"
nats_ping "$(connect_json altempl wrong)" | grep -q 'Authorization Violation' || fail "wrong password accepted"

echo "==> accepts every account user"
for u in "${users[@]}"; do
  nats_ping "$(connect_json "$u" "$(pw "$u")")" | grep -q 'PONG' || fail "$u rejected"
done

cross_publish() {
  local sub="$1" pub="$2" line got=""
  exec 4<>"/dev/tcp/127.0.0.1/$client_port"
  read -r -t 5 _ <&4
  printf 'CONNECT %s\r\nSUB smoke.isolation 1\r\nPING\r\n' "$(connect_json "$sub" "$(pw "$sub")")" >&4
  read -r -t 5 _ <&4
  exec 5<>"/dev/tcp/127.0.0.1/$client_port"
  read -r -t 5 _ <&5
  printf 'CONNECT %s\r\nPUB smoke.isolation 2\r\nhi\r\nPING\r\n' "$(connect_json "$pub" "$(pw "$pub")")" >&5
  read -r -t 5 _ <&5
  printf 'PING\r\n' >&4
  while read -r -t 2 line <&4; do
    case "$line" in MSG*) got=MSG ;; PONG*) break ;; esac
  done
  exec 4<&- 4>&- 5<&- 5>&-
  printf '%s' "$got"
}

echo "==> delivers within one account"
[ "$(cross_publish altempl altempl)" = "MSG" ] || fail "same-account message not delivered"

echo "==> isolates accounts"
[ -z "$(cross_publish openwa altempl)" ] || fail "message crossed from altempl to openwa"

echo "OK"
