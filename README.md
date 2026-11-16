# keil-stlink-wine

**Flash and debug STM32 boards with Keil µVision on Linux.** Keil runs under Wine, and an ST-Link connects as it would on Windows.

![platform](https://img.shields.io/badge/platform-Linux-blue)
![wine](https://img.shields.io/badge/Wine-%E2%89%A5%209-red)
![python](https://img.shields.io/badge/python-3-yellow)
![license](https://img.shields.io/badge/license-MIT-green)

Keil MDK runs fine under Wine: the editor, the compiler and building all work. But the moment you press
**Download** or **Debug** you get `No ST-LINK detected` / `ST-LINK connection error`.
This project fixes that with one install script and no changes to Keil itself.

---

## Contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Install](#install)
- [Set up your Keil project](#set-up-your-keil-project)
- [Troubleshooting](#troubleshooting)
- [Compatibility](#compatibility)
- [Uninstall](#uninstall)
- [FAQ](#faq)
- [Credits](#credits)

---

## How it works

Keil's ST-Link driver talks to the probe through Windows' **WinUSB**. In Wine, `winusb.dll` is only a stub,
so that route is dead.

But the same driver has a second route, **"Shareable ST-Link"** mode. There it doesn't touch USB at all and instead
talks to ST's `stlink-server` over a local TCP socket. This project provides a tiny **native Linux replacement for
that server**. Keil connects to it over localhost, and it drives the real USB device through libusb.

```
┌──────────────── Wine ────────────────┐
│ Keil µVision                         │
│   └─ ST-LINKIII-KEIL_SWO.dll         │
│        └─ STLinkUSBDriver.dll ───────┼──TCP localhost:7184──► stlink-tcp-bridge ──libusb──► ST-Link ──SWD──► MCU
└──────────────────────────────────────┘                        (native Linux)
```

| Component | What it does |
|---|---|
| `stlink-tcp-bridge` | Python 3 implementation of the `stlink-server` protocol. Its only dependency is libusb, loaded via `ctypes`. Listens on localhost only. |
| `stlinkserver.exe` | Do-nothing stub. ST's DLL launches `stlinkserver.exe` before connecting and gives up if the file is missing. Source: `stlinkserver-stub.c`. |
| `stlink-tcp-bridge.service` | systemd user service that starts the bridge at login. |
| `49-stlink.rules` | udev rule that lets your user access ST-Link probes without root. |
| `keil-shared` | Helper that enables shared mode in existing Keil projects. |

## Requirements

- Linux with **Keil MDK 5** installed in a Wine prefix (default `~/.wine`)
- **Wine** (tested with 11.x)
- **python3** and **libusb-1.0**. Both are preinstalled on most distros.
- sudo, once, for the udev rule
- *(optional)* a systemd user session. Without one, start the bridge yourself.

## Install

```sh
git clone https://github.com/ignacioAyala/keil-stlink-wine.git
cd keil-stlink-wine
./install.sh
```

Using a different Wine prefix?

```sh
WINEPREFIX=~/my-keil-prefix ./install.sh
```

Then **unplug and replug** the ST-Link so the new udev rule applies.

To check that it worked:

```sh
systemctl --user status stlink-tcp-bridge   # should be "active (running)"
lsusb | grep 0483                           # your ST-Link should be listed
```

## Set up your Keil project

You do this once per project.

1. Open the project and go to **Project → Options for Target…** (`Alt+F7`), then the **Debug** tab.
2. On the right, under **Use:**, select **ST-Link Debugger**, then click **Settings**.
3. Tick **☑ Shareable ST-Link**. Leave host/port at `localhost` / `7184`.
4. Untick **☐ Check version on start**. Firmware upgrades aren't possible in shared mode, so the check only produces a nag dialog.
5. Your probe should now appear under *Unit*, and your MCU under *SW Device*. Click **OK**, **OK**, then save.

You can also skip the GUI for step 3. With the project closed in Keil, run:

```sh
keil-shared path/to/project.uvprojx     # or a folder, to update every project in it
```

Now **Download (F8)** and **Debug (Ctrl+F5)** work as usual, including breakpoints, stepping, watch windows,
and the peripheral/register views.

## Troubleshooting

<details>
<summary><b>"ST-LINK connection error" or nothing under <i>Unit</i></b></summary>

- Is the bridge running? `systemctl --user status stlink-tcp-bridge`
- Is the probe connected? `lsusb | grep 0483` should show `0483:37xx`.
- Did the bridge restart while Keil was open? **Restart Keil**, because it doesn't reconnect on its own.
- Did you replug the probe after installing the udev rule?
</details>

<details>
<summary><b>"ST-Link firmware needs to be updated but it is not allowed in shared mode"</b></summary>

Untick **Check version on start** in the ST-Link settings. To actually upgrade the firmware, use ST's
STM32CubeProgrammer, which has a native Linux version.
</details>

<details>
<summary><b>"Device not found in available family packs"</b></summary>

The device pack (DFP) for your MCU isn't installed. Use Keil's Pack Installer, or download the `.pack` from
[keil.arm.com/packs](https://www.keil.arm.com/packs/) and unzip it into
`<prefix>/drive_c/users/<user>/AppData/Local/Arm/Packs/<Vendor>/<PackName>/<version>/`.
</details>

<details>
<summary><b>Seeing what's going on</b></summary>

Run the bridge in the foreground with protocol logging:

```sh
systemctl --user stop stlink-tcp-bridge
stlink-tcp-bridge -v
```

Every request from Keil and every USB command is printed. Restart the service when you're done.
</details>

<details>
<summary><b>Port 7184 is already in use</b></summary>

Run `stlink-tcp-bridge --port=7185` (edit `ExecStart` in the service file), and set the same port in Keil's
ST-Link settings.
</details>

## Compatibility

| Probe | USB ID | Status |
|---|---|---|
| ST-LINK/V2 (incl. clones) | `0483:3748` | ✅ tested: flash + debug |
| ST-LINK/V2-1 (Nucleo / Discovery on-board) | `0483:374b`, `374f`, `3752` | ⚠️ should work, untested |
| STLINK-V3 | `0483:374e`, `3753`, `3754`, `3757` | ⚠️ should work, untested |

Tested setup: Keil MDK 5 (ARMCLANG 6.24), Wine 11, CachyOS / Arch, STM32F072 with an ST-LINK/V2 clone (FW V2.J37).
If you've tried another probe or distro, please open an issue or PR with the result.

Not supported: SWIM (STM8).

## Uninstall

```sh
./install.sh --uninstall
```

This removes the bridge, the service, the helper, the stub exe and the udev rule.

## FAQ

**Does this modify Keil or any ST files?**
No. It only adds `stlinkserver.exe` in `Program Files\STMicroelectronics\stlink_server\` inside the Wine prefix.

**Is the bridge exposed on my network?**
No. It binds to `127.0.0.1` and `::1` only.

**Why not OpenOCD or pyOCD?**
They work well natively, but many courses and companies use Keil projects, Keil's debugger UI and its flash
algorithms. This lets you keep that workflow unchanged.

**Can several programs use the probe at once?**
In principle, yes: that's what shared mode is for, and the bridge serialises USB access. In practice, use one
debugger at a time.

## Credits

- The TCP protocol is documented by [OpenOCD](https://openocd.org)'s `stlink_usb.c` (stlink-server backend).
- The quirks of ST's `STLinkUSBDriver.dll` (75-byte device-info request, a device id that must be non-zero,
  a 12-byte open request) were worked out by tracing and disassembling the DLL's TCP path.

Not affiliated with Arm/Keil or STMicroelectronics. Keil, µVision, ST-LINK and STM32 are trademarks of their
respective owners.

## License

[MIT](LICENSE)
