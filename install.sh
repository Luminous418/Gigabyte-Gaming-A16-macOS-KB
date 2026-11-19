#!/bin/sh
# Install the GIGABYTE GAMING A16 keyboard backlight tool on macOS.
#
# No root required: everything goes into ~/.local/bin and ~/Library.
# No kext, no SIP changes, no EFI changes.
#
# Usage:
#   ./install.sh            install
#   ./install.sh uninstall  remove everything it created

set -eu

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
LABEL="com.github.luminous418.gigabyte-a16-kbd"
PLIST_SRC="$REPO_DIR/launchd/$LABEL.plist"

BIN_DIR="$HOME/.local/bin"
TOOL="$BIN_DIR/gigabyte-kbd"
AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_DST="$AGENTS_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
LOG="$LOG_DIR/gigabyte-kbd.log"

PYTHON=$(command -v python3 || true)

bail() { printf 'error: %s\n' "$1" >&2; exit 1; }

uninstall() {
    printf '==> Removing LaunchAgent\n'
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null \
        || launchctl unload "$PLIST_DST" 2>/dev/null \
        || true
    rm -f "$PLIST_DST"
    printf '==> Removing tool\n'
    rm -f "$TOOL"
    printf 'Done. Config and log left in place:\n'
    printf '  %s\n  %s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/gigabyte-kbd.conf" "$LOG"
}

[ "${1:-install}" = "uninstall" ] && { uninstall; exit 0; }

[ -n "$PYTHON" ] || bail "python3 not found (install the Command Line Tools: xcode-select --install)"
[ -x "$REPO_DIR/gigabyte-kbd" ] || bail "gigabyte-kbd not found in $REPO_DIR"

printf '==> Installing tool into %s\n' "$BIN_DIR"
mkdir -p "$BIN_DIR" "$AGENTS_DIR" "$LOG_DIR"
install -m 0755 "$REPO_DIR/gigabyte-kbd" "$TOOL"

printf '==> Checking the device\n'
"$PYTHON" "$TOOL" info || bail "device not found - is the keyboard connected?"

printf '==> Applying the startup colour now\n'
"$PYTHON" "$TOOL" startup || printf '    (warning: startup colour failed, continuing)\n'

printf '==> Installing LaunchAgent\n'
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
sed -e "s|__PYTHON__|$PYTHON|g" \
    -e "s|__TOOL__|$TOOL|g" \
    -e "s|__LOG__|$LOG|g" \
    "$PLIST_SRC" > "$PLIST_DST"
plutil -lint "$PLIST_DST" >/dev/null || bail "generated plist is invalid"

if launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null; then
    :
else
    launchctl load -w "$PLIST_DST" || bail "could not load the LaunchAgent"
fi

printf '\n==> Done.\n\n'
printf '  Tool:   %s\n' "$TOOL"
printf '  Agent:  %s\n' "$PLIST_DST"
printf '  Config: %s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/gigabyte-kbd.conf"
printf '  Log:    %s\n\n' "$LOG"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) printf 'NOTE: %s is not on your PATH. Add this to ~/.zshrc:\n\n' "$BIN_DIR"
       printf '  export PATH="$HOME/.local/bin:$PATH"\n\n' ;;
esac

printf 'Try it:\n'
printf '  %s color 00aaff\n' "$TOOL"
printf '  %s color ff0000 --intensity 128\n' "$TOOL"
printf '  %s off\n' "$TOOL"
printf '  %s info\n' "$TOOL"
