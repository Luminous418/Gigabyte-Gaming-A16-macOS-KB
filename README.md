# GIGABYTE GAMING A16 — RGB keyboard backlight for macOS

macOS port of [Gigabyte-Gaming-A16-Linux-KB-Drivers](https://github.com/Luminous418/Gigabyte-Gaming-A16-Linux-KB-Drivers).

Controls the RGB keyboard backlight of the **GIGABYTE GAMING A16 (GA6H)** on macOS
through the standard **Microsoft HID LampArray** protocol (`Usage Page 0x59`,
`Usage 1`).

No kext. No SIP changes. No EFI/OpenCore changes. Pure userspace, Python 3 only.

---

## The problem

The keyboard is a USB HID device (`VID 0414`, `PID 8105` here). Its backlight is
not an LED class device and it is not driven by any OS driver: **host software**
has to push the state. On Windows, Gigabyte Control Center / GiMate does that at
startup. Nothing else does, so after a cold boot the backlight stays off.

macOS exposes the LampArray interface already:

```
$ ./gigabyte-kbd detect --list
0x1d73       0x414    0x8105   0x59     1          USB-HID Keyboard   <== LampArray
```

So the whole job is sending two HID feature reports from userspace.

## Install

```sh
./install.sh
```

That installs the tool to `~/.local/bin`, applies the startup colour once, and
registers a `LaunchAgent` so it is re-applied at every login.

Uninstall with `./install.sh uninstall`.

## Usage

```sh
gigabyte-kbd info                        # lamp array attributes (read-only)
gigabyte-kbd selftest                    # diagnostics, writes nothing
gigabyte-kbd on                          # white, full brightness
gigabyte-kbd color ff0000                # red
gigabyte-kbd color 00ff00 --intensity 128 # green at half brightness
gigabyte-kbd off                         # backlight off
gigabyte-kbd startup                     # fixed startup colour (00aaff)
gigabyte-kbd auto                        # hand control to the firmware
gigabyte-kbd color 00aaff --auto         # set colour, then autonomous mode
gigabyte-kbd restore                     # re-apply the last saved colour
```

`--debug` shows every feature report and its `IOReturn`.

## What this machine reports

```
Lamp count:   1
Kind:         Notification (6)
Bounding box: 12000x16000x2000 um
Min interval: 100 us
```

A **single zone** covering a key-sized region. Brightness has to be emulated by
scaling RGB, because the LampArray intensity channel is effectively on/off here
— same quirk the Linux version documents.

## Report map

Decoded from the device's 327-byte report descriptor:

| ID | Report | Size (incl. ID) | Direction |
|----|--------|-----------------|-----------|
| `0x01` | LampArrayAttributes | 23 | read |
| `0x02` | LampAttributesRequest | 3 | write |
| `0x03` | LampAttributesResponse | 29 | read |
| `0x04` | MultiZoneUpdate | 51 | write |
| `0x05` | LampRangeUpdate | 10 | write |
| `0x06` | LampArrayControl (AutonomousMode) | 2 | write |

`MaxFeatureReportSize = 51` matches report `0x04`'s data size **without** the ID.

## The one real gotcha: IOKit wants the report ID inside the buffer

This is the only non-obvious part of the port and it cost the most time.

Apple's `IOHIDDeviceSetReport` / `IOHIDDeviceGetReport` headers say the report
ID is a separate argument and must **not** be in the data buffer:

```c
IOReturn IOHIDDeviceSetReport(IOHIDDeviceRef device,
                              IOHIDReportType reportType,
                              CFIndex reportID,
                              const uint8_t *report,
                              CFIndex reportLength);
```

On this keyboard that is wrong in both directions.

**Reading** — `GetReport(0x01)` rejects a 22-byte buffer with `0xE00002E8` and
only accepts **23** bytes, handing back the report ID itself as byte `[0]`:

```
GetReport size=22 rc=0xE00002E8 returned=22 data=00 00 00 ...
GetReport size=23 rc=0x00000000 returned=23 data=01 01 00 e0 2e 00 00 80 3e ...
                                                  ^^ report ID
                                                     ^^^^^ LampCount = 1
```

**Writing** — with the "documented" form (ID separate, 9-byte buffer for report
`0x05`) every call returns `kIOReturnSuccess` but the firmware **silently
ignores it** and the backlight never lights. Including the ID in the buffer
(10 bytes) works.

So: `IOReturn == 0` is **not** proof that the device accepted a write. The tool
therefore prefers the full-report form and keeps the other as a fallback,
selectable with `GIGABYTE_KBD_CONVENTION=in-buffer|separate` for debugging.

### Verifying the write path without a light meter

`AutonomousMode` (report `0x06`) is **not readable** on this firmware
(`GetReport` → `0xE0005000`), so there is no direct read-back of state. What did
prove the SET path reaches the firmware is the request/response pair:

```
SetReport(0x02, LampId=0)  ->  GetReport(0x03) = pos=(3000,8000,1000) um,
                                                 latency=4000 us, programmable=1
```

Also useful as a sanity check: writing to report `0x01` (declared `Const`) is
rejected with `0xE00002ED`, which shows validation is real and errors do surface.

## Differences from the Linux version

| Linux | macOS |
|---|---|
| `/dev/hidrawN` + `HIDIOCSFEATURE`/`HIDIOCGFEATURE` | `IOHIDDeviceGetReport`/`SetReport` via IOKit |
| udev rule for `input` group | not needed |
| systemd user unit | `LaunchAgent` |
| `report_descriptor` file per hidraw node | `ReportDescriptor` device property |
| matches VID + `b"\x05\x59"` in descriptor | matches VID + `PrimaryUsagePage 0x59` + `PrimaryUsage 1` |

Everything else — colour parsing, RGB brightness scaling, autonomous mode, config
file format — is the same, and the config lives at `~/.config/gigabyte-kbd.conf`
just like on Linux.

## Known limitations

- **Single zone.** This SKU reports `LampCount = 1`, so there is no per-key or
  multi-zone control to expose.
- **Cold boot.** After a full shutdown the EC forgets the colour; the
  `LaunchAgent` re-applies it at login. There is no way to set it before login
  without a firmware-stored colour.
- **`Fn+Space`** only works in autonomous mode (`auto` / `--auto`), and then it
  uses the firmware's own stored colour — the one Windows GiMate last saved —
  not the one set from here.
- **Sleep/wake.** `launchd` has no wake trigger. If the backlight does not come
  back after sleep, install `sleepwatcher` (`brew install sleepwatcher`) and add
  `gigabyte-kbd restore` to `~/.wakeup`.
- **`IOReturn` is unreliable for writes.** See above.

## Credits

Protocol work, report map and the Fn+Space/autonomous-mode behaviour all come
from the original Linux driver by [Luminous418](https://github.com/Luminous418).
MIT licensed, same as upstream.
