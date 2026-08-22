# SportsOS ESP32 Scoreboard Firmware

Milestone 11.1 establishes the hardware-independent firmware protocol core.

## Design rules

- SportsOS remains authoritative.
- ESP32 maintains a local display copy of the latest authoritative state.
- MQTT protocol version is currently `1`.
- Device state includes game assignment, score, period, clock and horn state.
- Local clock ticking is presentation behavior only; new server state always re-anchors it.
- Reconnect recovery is handled by the SportsOS API/MQTT gateway.
- Hardware pin mappings are intentionally not defined in Milestone 11.1.

## Supported commands

- `SET_GAME`
- `SET_SCORE`
- `SET_CLOCK`
- `SET_PERIOD`
- `HORN`
- `SYNC_STATE`

## Next firmware milestones

Milestone 11.2 will add JSON/MQTT serialization and parsing compatible with the SportsOS 10.x device contract.

Later firmware milestones will add Wi-Fi provisioning, MQTT connection management, display drivers, horn output, watchdog/recovery and OTA updating.

## Milestone 11.2 — MQTT JSON codec

The firmware now contains a JSON codec compatible with the SportsOS scoreboard MQTT contract.

### Command parsing

Supported JSON command types:

- `SET_GAME`
- `SET_SCORE`
- `SET_CLOCK`
- `SET_PERIOD`
- `HORN`
- `SYNC_STATE`

Required command fields include:

- `protocolVersion`
- `commandId`
- `type`

### Device publications

The codec can serialize:

- authoritative device state
- command acknowledgements
- retained presence state
- telemetry

ArduinoJson is used only for serialization/deserialization. The underlying scoreboard state machine remains independent of the JSON library and hardware drivers.

## Milestone 11.3 — Wi-Fi / MQTT runtime

The ESP32 firmware now includes the device runtime responsible for connectivity and MQTT transport.

### Runtime responsibilities

- connect and reconnect Wi-Fi
- connect and reconnect MQTT
- subscribe to the per-device command topic
- publish retained online/offline presence
- publish retained device state
- publish command acknowledgements
- publish periodic telemetry
- apply SportsOS commands through the Milestone 11.1 protocol core
- re-publish authoritative device state after an applied command

### MQTT topics

For device `<deviceId>`:

- `sportsos/scoreboards/<deviceId>/command`
- `sportsos/scoreboards/<deviceId>/ack`
- `sportsos/scoreboards/<deviceId>/state`
- `sportsos/scoreboards/<deviceId>/telemetry`
- `sportsos/scoreboards/<deviceId>/presence`

### Credentials

Real Wi-Fi and MQTT credentials must not be committed to source control.

Milestone 11.3 uses build-time configuration placeholders only. A later provisioning milestone will provide a local configuration workflow suitable for deployed scoreboard hardware.

## Milestone 11.4 — Local provisioning / configuration

The scoreboard can now enter a local Wi-Fi access-point setup mode when no valid configuration exists.

### Provisioning behavior

When configuration is missing, the ESP32 creates an access point named:

`SportsOS-Scoreboard-XXXXXX`

where the suffix is derived from the device chip ID.

The local setup portal provides fields for:

- scoreboard device ID
- Wi-Fi SSID
- Wi-Fi password
- MQTT host
- MQTT port
- optional MQTT username
- optional MQTT password

Configuration is stored locally using ESP32 `Preferences` / NVS.

### Local routes

- `GET /` — setup form
- `POST /save` — validate and persist configuration
- `GET /status` — local configuration status
- `POST /reset` — erase device configuration and restart

### Security behavior

- credentials are stored locally on the ESP32
- real secrets are not committed to the SportsOS source repository
- password fields are never echoed back into the setup form
- blank password fields preserve previously stored secrets
- the configuration portal is intended for local setup only

## Milestone 11.5 — Connectivity watchdog / failsafe runtime

The firmware now tracks connectivity health independently from the scoreboard state machine.

### Health states

- `Healthy`
- `WifiLost`
- `MqttLost`
- `StaleAuthoritativeState`
- `RecoveryRequired`

### Failsafe behavior

- short Wi-Fi and MQTT interruptions are tolerated during a grace period
- prolonged transport loss moves the device to a degraded/recovery state
- the display may continue projecting the last known clock locally
- stale authoritative state is explicitly detectable
- reconnecting does not invent new score, period, or game state
- SportsOS server synchronization remains authoritative

Milestone 11.6 will expose these health states to the physical display/status indicators and add safe operator-visible hardware diagnostics.

## Milestone 11.6 — Physical display / status driver contract

The firmware now has a hardware abstraction layer between SportsOS state and physical scoreboard electronics.

### Display frame

The hardware driver receives:

- home score
- away score
- period
- remaining clock time
- clock running state
- horn state
- game assignment presence
- connectivity / stale-state health

### Driver responsibilities

Concrete hardware drivers implement:

- initialization
- score/period/clock rendering
- horn output
- connectivity/status indicators
- clear/reset behavior

No GPIO pins, LED protocols, segment drivers, or relay assumptions are part of the shared contract.

A `NullScoreboardDisplayDriver` is included for testing and hardware-independent firmware development.

Milestone 11.7 will add the first concrete physical output implementation and configurable hardware mapping.

## Milestone 11.7 — Configurable GPIO output driver

The first concrete physical output driver is now available.

### Supported low-voltage digital outputs

- horn trigger output
- normal/healthy status output
- Wi-Fi-lost status output
- MQTT-lost status output
- stale-state status output
- recovery-required status output

Each output supports:

- configurable ESP32 pin
- enabled/disabled state
- active-high or active-low behavior

### Safety behavior

The firmware initializes configured outputs to their inactive state.

The shared driver validates output-capable GPIO numbers before startup.

This milestone defines only low-voltage ESP32 GPIO signaling. It does not define or assume mains-voltage wiring, contactors, power switching, or external scoreboard electrical design.

### Display rendering

Score, period and clock values remain available through `DisplayFrame`, but no specific numeric display chipset is selected yet.

Milestone 11.8 will add configurable hardware profiles and a concrete score/clock display implementation while preserving the shared driver contract.

## Milestone 11.8 — Hardware profiles / numeric display driver

The firmware now supports named hardware profiles and a concrete numeric scoreboard display layer.

### Included profiles

- `minimal-bench`
- `standard-hockey`

Profiles define:

- score digit counts
- period digit count
- clock minute/second digit counts
- numeric display backend type
- horn availability
- status indicator availability
- leading-zero preferences

### Numeric display snapshot

`NumericScoreboardDisplayDriver` converts the shared `DisplayFrame` into:

- home score
- away score
- period
- clock minutes
- clock seconds
- clock running state
- display health state

The driver remains backend-extensible. No high-current display wiring or mains-power switching is defined here.

Milestone 11.9 will add a concrete low-voltage shift-register / multiplexed segment backend and a host-side firmware behavior simulator.

## Milestone 11.9 — Segment backend / firmware behavior simulator

The firmware now includes a concrete low-voltage seven-segment output backend using a generic shift-register bus.

### Segment backend

The backend supports:

- configurable data pin
- configurable clock pin
- configurable latch pin
- active-high or active-low segment logic
- score digits
- period digit
- clock minute/second digits

The implementation uses only low-voltage ESP32 digital signaling.

### Host-side behavior simulator

`firmware/esp32-scoreboard/simulator` mirrors the core display behavior without requiring PlatformIO or ESP32 hardware.

It validates:

- authoritative state to numeric display conversion
- fixed-width score/clock rendering
- local clock projection
- stop-at-zero behavior

Milestone 11.10 will add firmware diagnostics and closeout integration before real-device flashing.

## Milestone 11.10 — Firmware diagnostics / hardware closeout

The firmware now exposes a common diagnostic snapshot containing:

- uptime
- Wi-Fi RSSI
- free heap
- Wi-Fi connectivity
- MQTT connectivity
- authoritative-state staleness
- recovery-required state
- protocol connection state
- connectivity watchdog health
- device ID
- current game assignment

A physical hardware validation checklist is included in `HARDWARE-VALIDATION-CHECKLIST.md`.

### Milestone 11 closeout status

Repository-side firmware architecture is now complete through:

- protocol state machine
- MQTT JSON codec
- Wi-Fi/MQTT runtime
- local provisioning
- connectivity watchdog
- display abstraction
- GPIO outputs
- hardware profiles
- numeric display layer
- seven-segment backend
- host-side behavior simulator
- firmware diagnostics

PlatformIO compilation and real ESP32 flashing remain the final hardware-specific validation steps.

## Milestone 12.1 — Containerized PlatformIO build toolchain

PlatformIO no longer needs to be installed directly on the Unraid host.

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/build-in-docker.sh
```

The script:

1. builds a small local Docker image containing PlatformIO
2. mounts the firmware directory into the container
3. persists PlatformIO toolchain/cache data in the Docker volume `sportsos_platformio_core`
4. compiles the `esp32dev` firmware target
5. leaves build artifacts in `firmware/esp32-scoreboard/.pio/build/esp32dev`

Expected firmware binary:

`firmware/esp32-scoreboard/.pio/build/esp32dev/firmware.bin`

This approach keeps the Unraid host clean and makes the firmware build reproducible.

## Milestone 12.2 — Flash packaging / ESP32 deployment

A successful PlatformIO build can now be packaged into a timestamped release under:

`firmware/esp32-scoreboard/releases/`

Each package contains:

- `firmware.bin`
- `firmware.elf` when available
- bootloader image when available
- partition table when available
- `boot_app0.bin` when available
- `SHA256SUMS.txt`
- `flash-layout.txt`

### Flash from Unraid without host PlatformIO

Connect the ESP32 USB serial device to the Unraid host and identify its device node.

Common examples:

- `/dev/ttyUSB0`
- `/dev/ttyACM0`

Then run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/flash-with-docker.sh /dev/ttyUSB0
```

The script uses the same Dockerized PlatformIO toolchain from Milestone 12.1.

Do not run the flash command until an actual ESP32 is connected and the correct serial device has been identified.

## Milestone 12.3 — Device enrollment / first-boot verification

Newly flashed scoreboard devices now have a first-boot identity contract.

The firmware identity contains:

- device ID
- firmware version
- ESP32 chip ID

The API exposes enrollment endpoints:

- `GET /scoreboard-devices/enrollment`
- `GET /scoreboard-devices/enrollment/:deviceId`
- `POST /scoreboard-devices/enrollment/first-boot`
- `POST /scoreboard-devices/enrollment/:deviceId/verify`
- `POST /scoreboard-devices/enrollment/:deviceId/reject`

The dashboard includes:

`/scoreboards/enrollment`

A newly flashed scoreboard should remain `PENDING` until an operator confirms the expected device ID and chip ID.

Verified devices can then proceed to game assignment and normal scoreboard operations.

## Milestone 12.4 — Enrollment persistence / device claim security

Scoreboard enrollment state is now persistent across API restarts.

Enrollment records are stored under the API data directory in:

`scoreboard-enrollments.json`

### Claim security

Verification now requires a one-time claim token.

Flow:

1. device sends first-boot identity
2. server records device as `PENDING`
3. operator requests a one-time claim token
4. token is stored only as a SHA-256 hash
5. verification consumes the token
6. consumed tokens cannot be reused
7. verified device ID + chip ID becomes the trusted enrollment identity

A verified device that later reports the same device ID with a different chip ID is rejected.

The firmware contract also supports serializing a claim-verification payload.

## Milestone 12.7 — First-boot enrollment transport binding

The ESP32 runtime now actively registers its first-boot identity with SportsOS.

### Runtime flow

After provisioning and Wi-Fi connection:

1. firmware builds its device identity
2. ESP32 POSTs identity to:
   `POST /scoreboard-devices/enrollment/first-boot`
3. ESP32 reads the returned enrollment state
4. firmware periodically refreshes:
   `GET /scoreboard-devices/enrollment/:deviceId`
5. `PENDING` devices retry safely
6. `VERIFIED` devices stop enrollment polling
7. `REJECTED` devices stop enrollment polling
8. transport failures retry after a configured interval

The default local API base URL is:

`http://192.168.5.3:4001`

It can be overridden at firmware build time using `SPORTSOS_API_BASE_URL`.

This milestone binds the previously separate firmware identity contract to the SportsOS enrollment API.

## Milestone 12.8 — Verified enrollment runtime gate

The ESP32 firmware now separates:

- provisioning connectivity
- enrollment transport
- authoritative SportsOS scoreboard runtime

A newly configured device may join Wi-Fi and contact the enrollment API, but it does **not** start the normal MQTT/game runtime until the enrollment state is `VERIFIED`.

### Gate behavior

- `PENDING` → authoritative runtime blocked
- transport error → authoritative runtime blocked
- `VERIFIED` → authoritative runtime starts
- `REJECTED` → authoritative runtime remains blocked

This prevents a newly flashed or untrusted device from subscribing to live scoreboard commands before its physical identity has been reviewed and claimed in SportsOS.

The host-side firmware simulator includes the same runtime-gate behavior.

## Milestone 12.10 — Device lifecycle / deployment closeout

SportsOS now defines the complete scoreboard trust lifecycle.

Enrollment states include:

- `PENDING`
- `VERIFIED`
- `REJECTED`
- `RETIRED`

A verified device may be explicitly retired. Retirement invalidates the operational trust relationship and blocks verified-device authorization.

A retired device may be reactivated, which moves it back to `PENDING`. It must receive a new one-time claim token and be verified again before authoritative scoreboard operations are permitted.

See:

`DEPLOYMENT-READINESS-CHECKLIST.md`

for the full Milestone 12 deployment release gate.

## Milestone 13.1 — OTA firmware release / update contract

SportsOS now defines the shared contract for remotely managed scoreboard firmware updates.

Release channels:

- `stable`
- `beta`
- `development`

Firmware update states:

- `IDLE`
- `AVAILABLE`
- `DOWNLOADING`
- `VERIFYING`
- `READY_TO_INSTALL`
- `INSTALLING`
- `REBOOTING`
- `SUCCEEDED`
- `FAILED`

Every OTA release includes:

- release ID
- semantic firmware version
- target hardware profile
- release channel
- SHA-256 firmware digest
- firmware size
- mandatory/optional flag
- creation timestamp

Create a release from the currently compiled firmware with:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/create-ota-release.sh 0.13.1 stable false
```

Release bundles are written under:

`firmware/esp32-scoreboard/releases/ota/`

Milestone 13.1 defines the release/update contract only. It does not yet download or install firmware on devices.

## Milestone 13.4 — Device OTA update check / offer binding

Verified ESP32 scoreboards now have a firmware update-check client.

The firmware periodically calls:

`GET /scoreboard-firmware/device-offer`

with:

- device ID
- current firmware version
- release channel
- hardware target

The API:

- requires a verified device identity
- selects the latest compatible release
- returns a device-bound artifact URL
- returns no offer when the device is current

The ESP32 validates the received offer using the Milestone 13.1 firmware update contract.

This milestone **does not install OTA firmware yet**. It only discovers and validates available releases.

Default firmware check interval:

`60 seconds`

Default channel:

`stable`

Default target:

`esp32dev`

## Milestone 13.5 — ESP32 OTA download / integrity verification

The ESP32 can now stage an offered firmware release into the OTA update partition.

The staging flow is:

1. download the device-bound artifact URL
2. verify HTTP success
3. verify declared byte count
4. stream bytes into the inactive OTA partition
5. calculate SHA-256 while streaming
6. verify the final byte count
7. verify SHA-256 against the release manifest
8. finalize the OTA partition only after integrity validation succeeds

If byte count or SHA-256 verification fails, the update is aborted and the OTA partition is not finalized for boot.

The firmware is **not rebooted automatically in Milestone 13.5**. Reboot/install policy is added in the next milestone.

`FirmwareUpdateClient::stageAvailableUpdate()` exposes staging to the runtime while keeping update discovery and binary transfer as separate operations.

## Milestone 13.10 — Firmware fleet acceptance / closeout

Milestone 13 provides the complete SportsOS firmware fleet-management foundation:

1. OTA release contract
2. release registry
3. artifact validation and serving
4. device update offer discovery
5. OTA download and integrity validation
6. controlled install/reboot policy
7. deployment reporting
8. firmware fleet dashboard
9. rollout orchestration
10. fleet acceptance gate

Run the full software + firmware acceptance gate with:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-fleet-acceptance.sh
```

Then run the container and browser workflow gates:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

See `FLEET-ACCEPTANCE-CHECKLIST.md` for the detailed closeout criteria.

## Milestone 14.1 — Hardware button / control input contract

SportsOS now defines a physical scoreboard input contract for ESP32-connected buttons and control panels.

Supported input intents:

- home score +1
- home score -1
- away score +1
- away score -1
- clock toggle
- clock start
- clock pause
- period +1
- period -1
- horn trigger

Physical controls do **not** directly mutate authoritative SportsOS game state.

Instead, firmware emits a control-input event containing:

- protocol version
- unique input ID
- device ID
- control intent
- sequence number
- occurrence time

SportsOS will later validate the device, assignment, game state, permissions, and duplicate sequence before applying any authoritative change.

The server returns one of:

- `ACCEPTED`
- `REJECTED`
- `IGNORED_DUPLICATE`

This preserves SportsOS as the authoritative game-state source while still supporting low-latency physical controls.

## Milestone 14.2 — GPIO button input / debounce driver

The ESP32 scoreboard firmware now includes a reusable GPIO button driver.

Capabilities:

- configurable GPIO pin per control
- configurable active-high / active-low input
- configurable `INPUT`, `INPUT_PULLUP`, and supported pull-down modes
- per-button debounce interval
- stable press and release edge detection
- no repeated event while a button remains held
- one callback surface for all mapped scoreboard controls

The default hardware profile uses active-low buttons with internal pull-ups and a 40 ms debounce interval.

Default pins:

- GPIO 32 — home score +1
- GPIO 33 — home score -1
- GPIO 25 — away score +1
- GPIO 26 — away score -1
- GPIO 27 — clock toggle
- GPIO 14 — period +1
- GPIO 13 — horn

Each pin can be overridden at compile time using the corresponding `SPORTSOS_BUTTON_*_PIN` macro.

Milestone 14.2 stops at validated local button events. It does **not** yet send those events to the SportsOS API or mutate authoritative game state. Transport and acknowledgement handling are introduced in Milestone 14.3.

## Milestone 14.9 — Physical control failure / offline retry policy

Physical control transport now includes a bounded firmware retry queue for temporary network/API failures.

Behavior:

- initial physical button press still receives one unique sequence number
- temporary transport failures are queued
- retries reuse the **same sequence number**
- server duplicate protection makes replay idempotent
- `ACCEPTED`, `REJECTED`, and `IGNORED_DUPLICATE` are terminal results
- transport errors and malformed responses are retryable
- queue capacity is 16 pending controls
- maximum attempts per control is 5
- retry delay uses bounded exponential backoff
- exhausted entries are dropped with a serial diagnostic

The retry queue does not invent new control events and does not mutate game state locally.

## Milestone 14.10 — Physical control acceptance / closeout

Milestone 14 provides the complete SportsOS physical scoreboard control foundation:

1. hardware control-input contract
2. GPIO/debounce driver
3. device-to-SportsOS input transport
4. authoritative command mapping
5. server-side game mutation binding
6. realtime scoreboard reconciliation
7. control audit and operator diagnostics
8. physical horn/output binding
9. offline retry/idempotency policy
10. acceptance and closeout

Run the full physical-control acceptance gate with:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash firmware/esp32-scoreboard/run-physical-control-acceptance.sh
```

Then run the container/browser gate:

```bash
docker compose up -d --build api dashboard
npm run test:e2e:docker
```

See `PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md` for the complete closeout criteria.
