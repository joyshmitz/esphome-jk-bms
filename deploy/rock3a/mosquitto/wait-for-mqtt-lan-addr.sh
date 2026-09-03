#!/bin/sh
# labems-hlj (B1), Codex-reviewed v2: before mosquitto binds, wait (up to 60s total) for
# BOTH non-loopback listener addresses to exist, so a slow WiFi/DHCP (.22 on wlp1s0) OR a
# slow Tailscale (100.75.41.122) after boot cannot make an unbindable listener take down the
# WHOLE broker (which would also drop 127.0.0.1 that deye-imex uses).
# Dead-WiFi is a total-LAN-outage case (Rock has no other uplink) — we do not hard-fail the
# unit; we let mosquitto try so the failure is visible via the normal start-limit.
LAN="192.168.88.22"
TS="100.75.41.122"
i=0
while [ "$i" -lt 60 ]; do
  if ip -4 addr show 2>/dev/null | grep -Fq "inet $LAN/" \
     && ip -4 addr show 2>/dev/null | grep -Fq "inet $TS/"; then
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done
echo "wait-for-mqtt-lan-addr: timeout after ${i}s; $LAN and/or $TS not up yet — letting mosquitto try" >&2
exit 0
