# SportsOS ESP32 Hardware Validation Checklist

Use this checklist before declaring a physical scoreboard device production-ready.

## 1. Power and boot

- ESP32 powers on reliably.
- Device does not enter a reboot loop.
- Serial boot output is readable.
- Provisioning AP appears when configuration is missing.
- Stored configuration survives power loss.

## 2. Local provisioning

- Setup AP name begins with `SportsOS-Scoreboard-`.
- Device ID can be saved.
- Wi-Fi SSID/password can be saved.
- MQTT host/port can be saved.
- Optional MQTT credentials can be saved.
- Stored passwords are not displayed back in the setup form.
- Reset clears local configuration.

## 3. Wi-Fi

- Device joins the configured local network.
- RSSI is visible through telemetry.
- Temporary Wi-Fi loss enters degraded/failsafe behavior.
- Wi-Fi recovery reconnects without manual restart.

## 4. MQTT

- Device subscribes to its command topic.
- Presence publishes online retained.
- MQTT last-will publishes offline retained.
- State publishes retained.
- Telemetry publishes non-retained.
- Acknowledgements publish for accepted/applied/rejected commands.
- MQTT reconnect restores command subscription.

## 5. Authoritative synchronization

- `SET_GAME` updates game assignment.
- `SET_SCORE` updates both scores.
- `SET_PERIOD` updates period.
- `SET_CLOCK` updates remaining time and running state.
- `HORN` toggles horn state.
- `SYNC_STATE` fully re-anchors device state.
- Reconnect causes the server to reconcile the device to current authoritative state.
- The device never invents score or period state while offline.

## 6. Clock behavior

- Running clock projects locally.
- Paused clock remains fixed.
- Clock stops at zero.
- Fresh server state re-anchors local clock projection.
- Stale-authoritative-state indication appears after the configured threshold.

## 7. Physical outputs

- Configured GPIO outputs initialize inactive.
- Horn output is inactive at boot.
- Status indicators match health state.
- Numeric display shows home score correctly.
- Numeric display shows away score correctly.
- Numeric display shows period correctly.
- Numeric display shows clock minutes/seconds correctly.

## 8. Fault recovery

- Wi-Fi loss is detected.
- MQTT loss is detected.
- Stale authoritative state is detected.
- Prolonged outage escalates to recovery-required.
- Restored connectivity clears the fault after authoritative state returns.

## 9. SportsOS integration

- Device appears on `/scoreboards/operations`.
- Device presence is ONLINE.
- Telemetry is visible.
- Game assignment is visible.
- Reconcile Now succeeds.
- Last acknowledgement is visible.
- Simulator and physical hardware produce equivalent state behavior.

## 10. Release gate

Do not mark physical firmware production-ready until:

- repository typecheck is green
- repository tests are green
- firmware behavior simulator tests are green
- actual firmware compiles with PlatformIO
- the target ESP32 board flashes successfully
- the physical checklist above passes on real hardware
