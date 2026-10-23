#!/usr/bin/env bash
#
# Install the keyboard-backlight idle timeout (applespi LED).
#
#   sudo ./install.sh                 # 30 s (default config)
#   sudo ./install.sh --timeout 60    # change it
#   sudo ./install.sh --uninstall
#   ./install.sh --check              # show LED + input devices, no root needed
#
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN=/usr/local/bin/kbd-backlight-timeout
UNIT=/etc/systemd/system/kbd-backlight-timeout.service
DEFAULT=/etc/default/kbd-backlight-timeout
SERVICE=kbd-backlight-timeout.service

DRY=0
UNINSTALL=0
TIMEOUT=""
ORIG_ARGS=("$@")

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
run() { printf '   + %s\n' "$*"; [ "$DRY" = 1 ] || "$@"; }

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y) ;;
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --check) exec python3 "$SRC/kbd-backlight-timeout" --check ;;
    --timeout)
      shift
      [ "$#" -gt 0 ] || { echo "--timeout needs a value" >&2; exit 2; }
      TIMEOUT="$1"
      ;;
    --timeout=*) TIMEOUT="${1#--timeout=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [ -n "$TIMEOUT" ] && { ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -gt 86400 ]; }; then
  echo "invalid timeout: $TIMEOUT (0..86400 seconds)" >&2
  exit 2
fi

if [ "$UNINSTALL" = 0 ] && [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then
  exec sudo bash "$0" "${ORIG_ARGS[@]}"
fi

if [ "$UNINSTALL" = 1 ]; then
  if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "${ORIG_ARGS[@]}"
  fi
  say "Removing the keyboard-backlight idle timeout…"
  run systemctl disable --now "$SERVICE" || true
  run rm -f "$UNIT" "$BIN" "$DEFAULT"
  run systemctl daemon-reload
  say "Removed. The keyboard backlight is back to normal."
  exit 0
fi

if [ "$DRY" = 0 ] && [ ! -x "$SRC/kbd-backlight-timeout" ]; then
  chmod +x "$SRC/kbd-backlight-timeout"
fi

say "Installing keyboard-backlight idle timeout…"
run install -d /usr/local/bin
run install -m755 "$SRC/kbd-backlight-timeout" "$BIN"
run install -m644 "$SRC/kbd-backlight-timeout.service" "$UNIT"

if [ -n "$TIMEOUT" ]; then
  run install -d "$(dirname "$DEFAULT")"
  if [ "$DRY" = 1 ]; then
    printf '   + write %s\n' "$DEFAULT"
  else
    cat >"$DEFAULT" <<EOF
# Seconds of no keyboard/touchpad/touch-bar input before the MacBook keyboard
# backlight is turned off.  The next input restores the saved brightness.
# 0 disables the timeout.
KBD_BACKLIGHT_TIMEOUT=$TIMEOUT
EOF
  fi
elif [ ! -e "$DEFAULT" ]; then
  run install -m644 "$SRC/kbd-backlight-timeout.default" "$DEFAULT"
fi

run systemctl daemon-reload
run systemctl enable "$SERVICE"
run systemctl restart "$SERVICE"

if [ "$DRY" = 0 ]; then
  echo
  say "Active. Current setting: $(grep -E '^KBD_BACKLIGHT_TIMEOUT=' "$DEFAULT" 2>/dev/null || echo 'KBD_BACKLIGHT_TIMEOUT=30')"
  echo "   Change it:  sudoedit $DEFAULT   (then: sudo systemctl restart $SERVICE)"
  echo "   Remove it:  sudo $SRC/install.sh --uninstall"
fi
