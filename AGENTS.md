<!-- Fork of syssi/esphome-jk-bms. This file lives ONLY on the `work` branch, never on `main`. -->
<!-- agent-mail: name=LavenderPuma project=/data/projects/esphome-jk-bms -->

# AGENTS.md — esphome-jk-bms (fork)

Operating instructions for coding agents working in this repository. This *is* your
operating manual — read it before touching code.

## 0. This is a FORK — do not pollute upstream

This checkout is our fork of the upstream ESPHome JK-BMS components project.

| Remote | URL | Role |
|--------|-----|------|
| `origin` | `github.com/joyshmitz/esphome-jk-bms` | **our fork** — we push here |
| `upstream` | `github.com/syssi/esphome-jk-bms` | **the wellspring** — fetch only, push is disabled |

Upstream push is hard-disabled (`remote.upstream.pushurl = DISABLED_no_pushing_to_upstream`).
Never re-enable it. We never open PRs to upstream from automation.

### Branch model (STRICT)

```
upstream/main ──(fast-forward only)──> main   (pristine mirror; ZERO of our commits)
                                         │ branch off
                                         ▼
                                       work    ──push──> origin/work   (our default work line)
                                         │
                                         ▼
                                    feature/*  (short-lived, branch off work)
```

- **`main` is a read-only mirror of `upstream/main`.** Never commit our work to `main`.
  If `main` ever gains one of our commits, `merge --ff-only upstream/main` breaks.
- **All our work lives on `work`** (and short-lived `feature/*` branches off it).
- This file (`AGENTS.md`) and any fork-only tooling exist on `work`, **not** on `main`.

### Sync from upstream (keep the mirror fresh)

```bash
git fetch upstream
git checkout main
git merge --ff-only upstream/main     # fast-forward only; must never create a merge commit
git push origin main                  # keep our fork's mirror in sync (optional)
git checkout work
git merge main                        # or: git rebase main — pull upstream changes into our work
```

If `--ff-only` refuses, `main` was contaminated with a local commit — move that commit to
`work` and hard-reset `main` back onto `upstream/main`.

### First push of the work branch

```bash
git push -u origin work
```

## 1. What this project is

ESPHome **external components** for Jikong (JK) BMS and NEEY/Heltec active balancers. Consumed
by end-user ESPHome configs via `external_components:`. Each dir under `components/` is a
drop-in component. Requires ESPHome ≥ 2025.11.0. There is **no firmware release artifact** —
"shipping" means the components validate, compile, lint, and pass tests against ESPHome `dev`.

Transports/protocols: UART-TTL classic JK (`jk_modbus`+`jk_bms`), BLE variants JK04 /
JK02_24S / JK02_32S (`jk_bms_ble`), NEEY/Heltec BLE balancers (`heltec_balancer_ble`), UART
balancer (`jk_balancer`+`jk_balancer_modbus`), display-port sniffer (`jk_bms_display`), and
JK-PB newest RS485 BMS (handled purely in YAML via stock `modbus_controller`, no custom C++).

## 2. Architecture (three layers)

1. **Transport** — `jk_modbus`, `jk_balancer_modbus` (`uart::UARTDevice`, frame/CRC, fan out via
   `on_*_data` callbacks); BLE drivers extend `ble_client::BLEClientNode` and reassemble GATT
   notifications in `assemble()`.
2. **Protocol decode** (frame parsing / byte-offset extraction):
   - BLE BMS: `components/jk_bms_ble/jk_bms_ble.cpp` — `decode_` dispatches on `frame_type =
     data[4]` to `decode_jk02_cell_info_` / `decode_jk04_cell_info_` / `decode_jk02_settings_` /
     `decode_jk04_settings_` / `decode_device_info_` / `decode_logbook_`.
   - UART BMS: `components/jk_bms/jk_bms.cpp` — `on_status_data_`.
   - BLE balancer: `components/heltec_balancer_ble/heltec_balancer_ble.cpp`.
   - UART balancer: `components/jk_balancer/jk_balancer.cpp`.
3. **ESPHome entity layer** — drivers hold nullable `sensor::/binary_sensor::/switch_::/number::/
   select::/text_sensor::` pointers + `set_*` setters; Python codegen (`__init__.py`, `sensor.py`,
   `binary_sensor.py`, `switch/`, `number/`, `select/`, `text_sensor.py`, `button/`) defines the
   YAML schema and wires setters in `to_code`. Error/enum labels are generated from
   `DEFAULT_ERRORS*` tuples in `__init__.py` and overridable via the `error_overrides:` YAML key
   (do not hand-edit the C++ tables). All drivers set `MULTI_CONF = True`.

### To add/modify a sensor or entity, touch the matched pair

1. Python platform file (schema + `cg.add(var.set_x_sensor(...))`), e.g. `components/jk_bms_ble/sensor.py`.
2. C++ driver header: pointer member + `set_*` setter (`jk_bms_ble.h` etc.).
3. C++ decoder: `publish_state_(...)` in the relevant `decode_*` / `on_status_data_`.
4. Regression test: capture a frame into `tests/components/<component>/frames_*.h`, assert in a
   `*_test.cpp`; extend an example YAML if it is a new protocol/firmware variant.

## 3. Build / test / lint

```bash
# C++ host unit tests (feeds captured frames through decoders — the real correctness harness)
./run-cpp-tests.sh                       # clones esphome@dev to /tmp, rsyncs components+tests, runs script/cpp_unit_test.py

# ESPHome config validate / compile a single example (faker configs need no hardware)
./test-esp32.sh                          # default esp32-example-faker.yaml
./test-esp8266.sh                        # default esp8266-example-faker.yaml
esphome -s external_components_source components config <some>.yaml

# Python schema/codegen tests
pytest tests/ -v

# Lint (mirrors CI): ruff/flake8/pylint/pyupgrade/yamllint/clang-format
pre-commit run --all-files
```

CI (`.github/workflows/ci.yaml`, push to `main`/PR/nightly): a `bundle` job copies `components/*`
into `esphome/esphome@dev` and shares the bundle; downstream jobs run lint, clang-tidy (ESP8266/
ESP32-arduino/ESP32-IDF), `pytest`, C++ unit tests, `esphome-config` over every `esp*.yaml`, and
`esphome-compile` over a representative subset. The root `esp32-*/esp8266-*.yaml` examples double
as user starting points and CI fixtures (`*-faker` = canned data, `*-debug`, `*-multiple-devices`,
`*-scanner`, versioned `v11/v14/v15/v19/jk04/...` = protocol/firmware variants).

## 4. Multi-agent coordination (MCP Agent Mail)

This autonomous repository participates in the laboratory program governed from
`/data/projects/deye-imex`; governance does not transfer ownership of this code. The stable
identity and primary bus are the exact marker above. The shared Product Bus is
`lab-ems-energy-stack`, and the canonical program snapshot is
`/data/projects/deye-imex/docs/where-we-are.md`.

The earlier `BluePine` registration on `/data/projects/felectra-deployment` is historical and
outside this Product; do not route new `lab-ems-energy-stack` traffic through it.

All three linked project buses contain recipient aliases `LavenderPuma`, `YellowHeron`, and
`BluePine`. Send from this bus only as `LavenderPuma`, with explicit recipients. Product Bus in
`am 0.3.30` is a federated read surface: create each update once on its owning repository bus;
use the same `thread_id` for cross-repo replies. Never use `broadcast`, and do not pass `topic`.
Shared threads use `lab-ems-energy-stack.shared.<kind>[.<subject>]`; repository-only threads use
`lab-ems-energy-stack.repo.esphome-jk-bms.<topic>`.

Program work status and dependencies live only in `/data/projects/deye-imex/.beads/` (prefix
`labems`). Do not run `br init` or `ee init` here. Update the governing status file only when
the program snapshot changes, and record the updater plus this repository's exact SHA.

Agent Mail coordination never authorizes a flash/deploy, broker LAN exposure, BMS command,
wiring change, or physical laboratory scenario. Those require explicit user authorization for
the exact action and the safety gates in `/data/projects/deye-imex/docs/scenarios.md`.
