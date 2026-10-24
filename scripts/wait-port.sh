#!/usr/bin/env bash
# Waits until a TCP port accepts connections — the readiness check for a server
# a run just started, in place of `sleep N && curl` loops that guess the delay.
#
#   wait-port.sh <port> [--timeout <s>] [--host <h>] [--pid <n>]
#
# Polls every 0.2 s through bash's /dev/tcp. --pid names the server's process:
# when it exits, the wait ends at once — a server that crashed at boot otherwise
# costs the whole timeout (a rust run lost 330 s that way). Output: one JSON
# line {port, open, waited_s, exited}. Exit 0 when open, 1 on timeout or exit,
# 2 on bad usage.

set -euo pipefail

PORT="${1-}" TIMEOUT=30 HOST=127.0.0.1 PID=""
[ $# -gt 0 ] && shift
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2-}"; shift 2 ;;
    --host) HOST="${2-}"; shift 2 ;;
    --pid) PID="${2-}"; shift 2 ;;
    *) echo "wait-port.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$PORT" in '' | *[!0-9]*) echo "wait-port.sh: <port> is required and numeric" >&2; exit 2 ;; esac
case "$TIMEOUT" in '' | *[!0-9]*) echo "wait-port.sh: --timeout takes whole seconds" >&2; exit 2 ;; esac
case "$PID" in *[!0-9]*) echo "wait-port.sh: --pid takes a process id" >&2; exit 2 ;; esac

waited_s() { local ms=$(( ($(date +%s%N) - start) / 1000000 )); printf '%d.%03d' $((ms / 1000)) $((ms % 1000)); }

start=$(date +%s%N)
deadline=$(( start + TIMEOUT * 1000000000 ))
while :; do
  if (exec 3<>"/dev/tcp/$HOST/$PORT") 2>/dev/null; then
    printf '{"port": %s, "open": true, "waited_s": %s, "exited": false}\n' "$PORT" "$(waited_s)"
    exit 0
  fi
  if [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then
    printf '{"port": %s, "open": false, "waited_s": %s, "exited": true}\n' "$PORT" "$(waited_s)"
    exit 1
  fi
  if [ "$(date +%s%N)" -ge "$deadline" ]; then
    printf '{"port": %s, "open": false, "waited_s": %s, "exited": false}\n' "$PORT" "$TIMEOUT"
    exit 1
  fi
  sleep 0.2
done
