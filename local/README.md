# local/ — deploy-конфіги нашого стенду (gitignored)

Дві плати **ESP32-C6** (Waveshare 1.47" LCD), по одній на нитку JK-BMS, читають по
BLE і публікують у MQTT. Схема — ратифікований `telemetry-v1` (deye-imex@f85d92f),
`esphome config` обох плат підтверджено валідним (YellowHeron, ESPHome 2026.8.2).

| Файл | Роль |
|---|---|
| `_jk-bms-common.yaml` | спільний пакет із усіма сутностями (сам не флешується) |
| `jk-bms-a.yaml` | плата A → String A → теми `jkbms/string_a/…`, акаунт `jk-bms-a` |
| `jk-bms-b.yaml` | плата B → String B → теми `jkbms/string_b/…`, акаунт `jk-bms-b` |
| `secrets.yaml.example` | шаблон секретів → скопіювати в `secrets.yaml` |

Джерело компонента — **github-пін нашого форку** (`@60e28f2`), тож конфіги
self-contained: потрібні лише ці 4 файли + `esphome`, репо клонувати не треба.

## Архітектура розгортання (оновлено 2026-08-31)

- **Живлення + прошивка — з Radxa Rock 3A по USB** (через SSH).
- **Канал даних — Bluetooth (до BMS) + Wi-Fi (до брокера `192.168.88.22:1883`, рішення B).**
- **BLE-нюанс:** власник наміряв нестабільний BLE із точки Rock 3A до обох BMS.
  Щоб зберегти живлення/прошивку з Radxa І стабільний BLE — вивести плату до
  батареї **активним USB-подовжувачем** (живлення й консоль тим самим кабелем),
  а не тримати біля корпусу Rock. Без контакту з корпусами BMS/шинами (ізоляція).
- Переконайся, що **Wi-Fi дістає** до фінального місця плати.

## Прошивка з Rock 3A (Armbian aarch64, по SSH)

```bash
# 0) на Rock: доступ до USB-serial (ESP32-C6 = нативний USB → /dev/ttyACM0)
sudo usermod -aG dialout "$USER"    # перелогінитись; або запускати з sudo

# 1) ESPHome
pipx install esphome                # або: pip3 install esphome  (Python ≥ 3.9)
#   альтернатива — контейнер (на Rock уже є rootless Podman):
#   podman run --rm -it --device /dev/ttyACM0 -v "$PWD":/config \
#     ghcr.io/esphome/esphome run jk-bms-a.yaml

# 2) секрети
cp secrets.yaml.example secrets.yaml && $EDITOR secrets.yaml

# 3) валідація і ПЕРШИЙ флеш по USB
esphome config jk-bms-a.yaml
esphome run    jk-bms-a.yaml        # обрати порт /dev/ttyACM0

# 4) BLE-декод одразу в логах (ще до брокера)
esphome logs   jk-bms-a.yaml
```

Наступні оновлення — OTA по Wi-Fi (`ota_password`). Плату №2 — так само, по одній.

## Знати

- **Заводська демо Waveshare** («Onboard parameter / Flash 4 MB / Wireless scan»)
  перезапишеться; LCD згасне (дисплей не конфігуруємо — опційно).
- **MQTT не пройде, доки LAN-слухач брокера на Rock не розгорнуто** (`labems-7f6.5`
  ухвалено, застосування — окрема транзакція власника). До того — BLE в USB-логах.
  Брокер: акаунт на плату (`jk-bms-a`/`jk-bms-b`), ACL `jkbms/string_<x>/#`.
- **Яка плата — яка нитка:** за `charging_cycles` (нитка 1 = 217, нитка 2 = 162).
  Плата №1 (власний MAC `E4:B0:63:40:C5:3C`) → спостереження `jkbms/string_a/#`.
  BMS-адреси у врапперах: A=`C8:47:80:19:0F:6F`, B=`C8:47:80:28:34:F3`.
- **protocol_version:** `JK02_24S` (hw 8.x) — звірити з text_sensor «hardware version».
- **Порядок (власник, 01.09):** транзакція брокера B → флеш №1 → перенесення +
  спостереження `string_a` → плата №2.
