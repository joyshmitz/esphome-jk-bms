# Mosquitto bind-on-boot guard (Rock 3A) — `labems-hlj`

Host-side systemd hardening so the MQTT broker on the lab **Radxa Rock 3A** reliably binds
**all three** listeners after a reboot, even when the WiFi LAN address comes up slowly.

> This is fork-only deployment tooling for our lab node — it lives on `work`, never on `main`.
> The broker itself, its ACL, passwords, listeners and the deye-imex bridge are **unchanged**;
> this only makes systemd wait for the listener addresses before mosquitto starts.

## The problem

Mosquitto 2.0 runs one process with three listeners on `:1883`:

| Address | Auth | Consumer |
|---|---|---|
| `127.0.0.1` | anonymous | deye-imex MQTT bridge (must never drop) |
| `100.75.41.122` (Tailscale) | anonymous | external EMS (n8n) |
| `192.168.88.22` (LAN, WiFi `wlp1s0`) | auth + ACL | the two ESP32-C6 JK-BMS boards |

`192.168.88.22` is a DHCP-reserved static IP on `wlp1s0` — the Rock's **only** LAN uplink
(Ethernet was removed). In mosquitto 2.0 a listener that cannot bind fails the **whole**
broker. So if `wlp1s0`/DHCP is slow to bring up `.22` after boot, mosquitto starts, cannot
bind `.22`, and takes down `127.0.0.1` (deye-imex) and the Tailscale listener with it —
rapid-failing into the systemd start-limit and staying **down until manual intervention**,
silently. The base unit already has `After/Wants=network-online.target`, but
`systemd-networkd-wait-online` does not guarantee WiFi DHCP has assigned `.22` by then.

## The fix (two files)

- **`wait-for-mqtt-lan-addr.sh`** → `/usr/local/sbin/` (`0755`): an `ExecStartPre` that waits
  (≤60 s total) until **both** non-loopback listener addresses (`192.168.88.22` **and**
  `100.75.41.122`) exist, then lets mosquitto bind. If they never appear (WiFi truly dead —
  a total-LAN-outage the Rock can't route around anyway) it `exit 0`s so mosquitto still tries
  and the failure surfaces normally, rather than blocking the unit forever.
- **`10-wait-lan.conf`** → `/etc/systemd/system/mosquitto.service.d/` (`0644`): wires the
  `ExecStartPre`, gives `TimeoutStartSec=120` headroom (a `[Service]` directive — see below),
  and sets `RestartSec=2`. It deliberately **keeps** the default start-limit: with the wait,
  the slow-`.22` case no longer rapid-fails, so the start-limit still correctly catches a
  *genuine* config/ACL/port error instead of retrying forever.

### Deployed SHA-256 (byte-exact to the files here)

```
fe6c09739e057eb060263cc62b221cb58bb558a994d3f90379be964f34edcdac  wait-for-mqtt-lan-addr.sh
153be5762efd25263223552e241dbd42de39f24bbc1292dc1bb30828774ec40d  10-wait-lan.conf
```

## Apply (config-only; exercised in a controlled reboot window)

```sh
install -m0755 wait-for-mqtt-lan-addr.sh /usr/local/sbin/wait-for-mqtt-lan-addr.sh
install -m0644 10-wait-lan.conf /etc/systemd/system/mosquitto.service.d/10-wait-lan.conf
systemctl daemon-reload          # NO restart — takes effect on the next mosquitto start
# verify:
systemctl show mosquitto -p TimeoutStartUSec -p StartLimitIntervalUSec -p ExecStartPre
```

## Codex review trail (independent second-model gate)

Reviewed by Codex (`gpt-5.6-sol`, reasoning ultra) before applying:

- **v1 → REVISE.** `StartLimitIntervalSec=0` would hide genuine config errors (infinite 2 s
  retry); only `.22` was waited for (not Tailscale); `ExecStartPre` counts against the start
  timeout; regex-dot `grep`; dead-WiFi all-or-nothing.
- **v2 → REVISE.** Addressed 4/5 (removed the start-limit disable; waits for both addresses in
  one ≤60 s loop; `grep -Fq`; timeout journal note) — but placed `TimeoutStartSec` under
  `[Unit]`, where **systemd ignores it**.
- **v3 → APPROVE.** Moved `TimeoutStartSec=120` to `[Service]` (verified live:
  `TimeoutStartUSec=2min`). The wait script stabilised at v2 (its logic didn't change v2→v3);
  only the drop-in's section placement did.

## DoD evidence (reboot window 2026-09-03)

Applied v3 config-only (MainPID unchanged → no restart). Then, in the window:

**3× soft `systemctl reboot`** — clean bind every time, `NRestarts=0`, all 3 listeners,
both strings + deye online, **empty post-diff** (guard SHA unchanged):

| # | Recovery | boot_id | NRestarts | Listeners | Strings | deye |
|---|---|---|---|---|---|---|
| 1 | 41 s | →6a1f1fe4 | 0 | 3/3 | A online/10 · B online/4 | online |
| 2 | 42 s | →6a68f8ee | 0 | 3/3 | A online/3 · B online/7 | online |
| 3 | 58 s | →93ac94b0 | 0 | 3/3 | A online/5 · B online/9 | online |

**Caveat (honest):** soft reboots kept the boards powered and `.22` came up fast, so these
prove *clean bind + zero regression + guard present and harmless* — not the slow-`.22` rescue.

**1× cold power-cycle (owner, v3 active)** — the real slow-`.22` / boards-repowered case:

Owner physically cut Rock power for ~10 s (boards repowered too), v3 active:

| Metric | Value |
|---|---|
| Power cut → box unreachable | 11:51:49Z |
| New boot_id | `1c31849e` (cold reboot confirmed) |
| Full recovery | **uptime ≈ 26 s** — mosquitto `active`, `NRestarts=0`, 3/3 listeners, `.22` up |
| Strings / bridge | A online/age=10 · B online/age=5 · deye online |
| mosquitto journal | `Starting` → `Started` in ~1 s; `ExecMainStartTimestampMonotonic ≈ 16 s` → the guard waited through early boot for `.22`+Tailscale, then bound cleanly; no timeout/failed lines |

So on a genuine cold boot (DHCP from scratch, boards repowered) the guard ran, waited ~16 s for
the addresses, and let mosquitto bind all three listeners with zero restarts. `.22` still came
up fast enough that the >60 s timeout branch was never stressed — but the guard demonstrably
works on a cold boot and does no harm.

Earlier context: an owner cold power-cycle at ~11:02Z (still on v1) recovered in ~5–6 min.
