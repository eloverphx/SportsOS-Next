# SportsOS ESP32 Flash Manifest

Generated package:

`firmware/esp32-scoreboard/releases/esp32dev-20260818-222220`

## Primary application image

- Application: `firmware.bin`
- Default application offset: `0x10000`

## Full flash layout

When all PlatformIO-generated images are present:

- `0x1000 bootloader.bin`
- `0x8000 partitions.bin`
- `0xE000 boot_app0.bin`
- `0x10000 firmware.bin`

## Integrity

SHA-256 hashes are stored in:

`firmware/esp32-scoreboard/releases/esp32dev-20260818-222220/SHA256SUMS.txt`

## Build source

The package was created from:

`firmware/esp32-scoreboard/.pio/build/esp32dev`

Do not flash binaries from a different build directory or board profile into this package.
