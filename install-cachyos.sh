#!/usr/bin/env bash
#
# t1-touchbar — CachyOS/Arch (pacman) installer
#
# Adapted from the upstream apt-based install.sh:
#   https://github.com/AJ-dev-i60/t1-touchbar
# Only the package-install step differs (pacman instead of apt); the DKMS build and
# the config files are identical to upstream.
#
# Run as root:   sudo bash install-cachyos.sh
#
set -euo pipefail

DKMS_NAME=apple-ib-drv
DKMS_VER=0.1
REPO="$(cd "$(dirname "$0")" && pwd)"
SRC="/usr/src/${DKMS_NAME}-${DKMS_VER}"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# ── root ────────────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || die "Run me as root:  sudo bash $0"

# ── preflight ───────────────────────────────────────────────────────────────
KREL="$(uname -r)"
[ -f "$REPO/apple-ib-drv/dkms.conf" ] || die "Can't find apple-ib-drv/ next to this script."

if command -v lsusb >/dev/null && lsusb 2>/dev/null | grep -qi '05ac:8600'; then
  say "T1 iBridge (05ac:8600) detected."
else
  say "WARNING: no T1 iBridge (05ac:8600) on USB — this is a MacBookPro13,x/14,x feature. Continuing anyway."
fi

command -v dkms >/dev/null || die "dkms not installed. Run:  sudo pacman -S --needed dkms"
[ -d "/usr/lib/modules/${KREL}/build" ] || die "Kernel headers for ${KREL} missing. Run:  sudo pacman -S linux-cachyos-headers"
say "Kernel: ${KREL}  (headers present)"

# ── Step 2: freeze guard FIRST ──────────────────────────────────────────────
# Written before the module can possibly exist or auto-load. A load without this runs
# ASOC.SOCW(1) and HARD-FREEZES the T1. The driver also defaults to skipping on T1 via
# DMI, so this is belt-and-suspenders. NEVER set skip_acpi_power=0.
say "Installing freeze guard -> /etc/modprobe.d/apple-touchbar.conf (skip_acpi_power=1)"
# Grab any idle timeout out of the old layout BEFORE the rewrite below replaces it.
IDLE_CONF=/etc/modprobe.d/apple-touchbar-idle.conf
legacy_idle=$(grep -E '^[[:space:]]*options[[:space:]]+apple_touchbar[[:space:]]+idle_timeout=' \
                /etc/modprobe.d/apple-touchbar.conf 2>/dev/null | tail -1 || true)
install -m644 "$REPO/apple-ib-drv/packaging/apple-touchbar.modprobe.conf" \
              /etc/modprobe.d/apple-touchbar.conf
# The idle timeout lives in a drop-in of its own so that rewriting the freeze-guard
# file above never reverts a timeout you chose. An existing value always wins.
if [ -e "$IDLE_CONF" ]; then
  say "Keeping your idle timeout: $(grep -E '^options ' "$IDLE_CONF" | tail -1 || true)"
elif [ -n "$legacy_idle" ]; then
  # a timeout lived in the file we just rewrote — carry it over instead of losing it
  say "Moving your idle timeout into ${IDLE_CONF}: ${legacy_idle}"
  { printf '%s\n\n' "# Touch Bar idle timeout (carried over from apple-touchbar.conf by the installer)."
    printf '%s\n' "$legacy_idle"; } > "$IDLE_CONF"
else
  install -m644 "$REPO/apple-ib-drv/packaging/apple-touchbar-idle.conf" "$IDLE_CONF"
fi

# ── Step 3: stage sources for DKMS ──────────────────────────────────────────
say "Staging driver sources -> ${SRC}"
install -d "$SRC"
cp "$REPO"/apple-ib-drv/{Makefile,apple-ibridge.c,apple-ibridge.h,apple-touchbar.c,hid-ids.h,dkms.conf} "$SRC"/

# ── Step 4: DKMS build + install ────────────────────────────────────────────
# Rebuild whenever the staged sources differ from the ones we last built. Without this
# a reinstall keeps the old .ko and driver fixes silently never take effect (dkms says
# "already installed" and skips straight past them).
DRV_SRCS=("$REPO"/apple-ib-drv/Makefile "$REPO"/apple-ib-drv/apple-ibridge.c
          "$REPO"/apple-ib-drv/apple-ibridge.h "$REPO"/apple-ib-drv/apple-touchbar.c
          "$REPO"/apple-ib-drv/hid-ids.h "$REPO"/apple-ib-drv/dkms.conf)
STAMP="$SRC/.source-stamp"
new_stamp=$(md5sum "${DRV_SRCS[@]}" | md5sum)
old_stamp=$(cat "$STAMP" 2>/dev/null || true)
need_build=0
dkms status "${DKMS_NAME}/${DKMS_VER}" 2>/dev/null | grep -q "${KREL}.*installed" || need_build=1
[ "$new_stamp" = "$old_stamp" ] || need_build=1
if [ "$need_build" = 1 ]; then
  say "DKMS: add"
  dkms add -m "$DKMS_NAME" -v "$DKMS_VER" 2>/dev/null || true
  say "DKMS: build (this compiles the module — may take a moment)"
  dkms build -m "$DKMS_NAME" -v "$DKMS_VER" --force
  say "DKMS: install"
  dkms install -m "$DKMS_NAME" -v "$DKMS_VER" --force
  printf '%s' "$new_stamp" > "$STAMP"
else
  say "DKMS: ${DKMS_NAME}/${DKMS_VER} already built from the current sources for ${KREL}."
fi

# ── Step 5: udev rule + autoload at boot ────────────────────────────────────
say "Installing udev rule -> /etc/udev/rules.d/99-ibridge.rules"
install -m644 "$REPO/apple-ib-drv/packaging/99-ibridge.rules" /etc/udev/rules.d/99-ibridge.rules
say "Enabling autoload -> /etc/modules-load.d/apple-touchbar.conf"
install -m644 "$REPO/apple-ib-drv/packaging/apple-touchbar.modules-load.conf" \
              /etc/modules-load.d/apple-touchbar.conf
udevadm control --reload
udevadm trigger

# ── summary ─────────────────────────────────────────────────────────────────
echo
say "Installed files:"
echo "   /etc/modprobe.d/apple-touchbar.conf        (skip_acpi_power=1 — freeze guard)"
echo "   /etc/modprobe.d/apple-touchbar-idle.conf   (idle_timeout — kept if you set one)"
echo "   /etc/udev/rules.d/99-ibridge.rules         (USB config 1 + no autosuspend)"
echo "   /etc/modules-load.d/apple-touchbar.conf    (load apple-ibridge at boot)"
echo "   ${SRC}/"
echo
dkms status || true
echo
say "A \"module verification failed / tainting kernel\" message later is EXPECTED and harmless (Secure Boot is off)."
say "Now REBOOT to finish:  sudo reboot"
echo "   The running session's usbhid already holds the iBridge interfaces, so the module can't"
echo "   bind live — the reboot lets apple-ibridge claim it early and the strip lights up."
