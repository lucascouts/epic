#!/usr/bin/env bash
# Waits until a TCP port accepts connections — the readiness check for a server
# a run just started, in place of `sleep N && curl` loops that guess the delay.
#
#   wait-port.sh <port> [--timeout <s>] [--host <h>]
#
# Polls every 0.2 s through bash's /dev/tcp. Output: one JSON line
# {port, open, waited_s}. Exit 0 when open, 1 on timeout, 2 on bad usage.

set -euo pipefail

PORT="${1-}" TIMEOUT=30 HOST=127.0.0.1
[ $# -gt 0 ] && shift
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2-}"; shift 2 ;;
    --host) HOST="${2-}"; shift 2 ;;
    *) echo "wait-port.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$PORT" in '' | *[!0-9]*) echo "wait-port.sh: <port> is required and numeric" >&2; exit 2 ;; esac
case "$TIMEOUT" in '' | *[!0-9]*) echo "wait-port.sh: --timeout takes whole seconds" >&2; exit 2 ;; esac

start=$(date +%s%N)
deadline=$(( start + TIMEOUT * 1000000000 ))
while :; do
  if (exec 3<>"/dev/tcp/$HOST/$PORT") 2>/dev/null; then
    waited=$(( ($(date +%s%N) - start) / 1000000 ))
    printf '{"port": %s, "open": true, "waited_s": %d.%03d}\n' "$PORT" $((waited / 1000)) $((waited % 1000))
    exit 0
  fi
  if [ "$(date +%s%N)" -ge "$deadline" ]; then
    printf '{"port": %s, "open": false, "waited_s": %s}\n' "$PORT" "$TIMEOUT"
    exit 1
  fi
  sleep 0.2
done
