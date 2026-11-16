#!/bin/sh
# Install / uninstall the Keil-under-Wine ST-Link bridge for the current user.
#   ./install.sh              install (asks for sudo once, for the udev rule)
#   ./install.sh --uninstall  remove everything
# WINEPREFIX defaults to ~/.wine.
set -e
cd "$(dirname "$0")"
PREFIX=${WINEPREFIX:-$HOME/.wine}
BIN=$HOME/.local/bin
UNIT=$HOME/.config/systemd/user
RULE=/etc/udev/rules.d/49-stlink.rules
STUB_DIRS="$PREFIX/drive_c/Program Files/STMicroelectronics/stlink_server
$PREFIX/drive_c/Program Files (x86)/STMicroelectronics/stlink_server"

if [ "$1" = --uninstall ]; then
  systemctl --user disable --now stlink-tcp-bridge 2>/dev/null || true
  rm -f "$BIN/stlink-tcp-bridge" "$BIN/keil-shared" "$UNIT/stlink-tcp-bridge.service"
  echo "$STUB_DIRS" | while IFS= read -r d; do rm -f "$d/stlinkserver.exe"; done
  [ -f "$RULE" ] && sudo rm -f "$RULE" && sudo udevadm control --reload
  echo "Uninstalled."; exit 0
fi

# deps
command -v python3 >/dev/null || { echo "need python3" >&2; exit 1; }
python3 -c "import ctypes; ctypes.CDLL('libusb-1.0.so.0')" 2>/dev/null \
  || { echo "need libusb-1.0 (e.g. pacman -S libusb / apt install libusb-1.0-0)" >&2; exit 1; }
[ -d "$PREFIX/drive_c" ] || { echo "Wine prefix not found: $PREFIX (set WINEPREFIX)" >&2; exit 1; }

# stub exe: build if a Windows cross compiler exists, else use the prebuilt one
if command -v zig >/dev/null; then
  zig cc -target x86-windows-gnu -Os -s -o stlinkserver.exe stlinkserver-stub.c
elif command -v i686-w64-mingw32-gcc >/dev/null; then
  i686-w64-mingw32-gcc -Os -s -o stlinkserver.exe stlinkserver-stub.c
fi
[ -f stlinkserver.exe ] || { echo "no stlinkserver.exe and no zig/mingw to build it" >&2; exit 1; }

install -Dm755 stlink-tcp-bridge "$BIN/stlink-tcp-bridge"
install -Dm755 keil-shared "$BIN/keil-shared"
echo "$STUB_DIRS" | while IFS= read -r d; do install -Dm755 stlinkserver.exe "$d/stlinkserver.exe"; done

if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  install -Dm644 stlink-tcp-bridge.service "$UNIT/stlink-tcp-bridge.service"
  systemctl --user daemon-reload
  systemctl --user enable stlink-tcp-bridge
  systemctl --user restart stlink-tcp-bridge
else
  echo "No systemd user session: start '$BIN/stlink-tcp-bridge &' yourself (e.g. from your autostart)."
fi

if ! cmp -s 49-stlink.rules "$RULE" 2>/dev/null; then
  echo "Installing udev rule (needs sudo)..."
  sudo install -m644 49-stlink.rules "$RULE"
  sudo udevadm control --reload && sudo udevadm trigger
  echo ">> Unplug and replug the ST-Link."
fi

cat <<EOF

Done. In Keil, per project:
  Options for Target (Alt+F7) > Debug > ST-Link Debugger > Settings
    [x] Shareable ST-Link     (or run: keil-shared path/to/project.uvprojx)
    [ ] Check version on start
Restart Keil if the bridge was (re)started while Keil was open.
EOF
