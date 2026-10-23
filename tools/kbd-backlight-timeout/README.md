# Keyboard backlight idle timeout

The T1 MacBook's keyboard backlight is exposed by `applespi` as:

```
/sys/class/leds/spi::kbd_backlight/brightness
```

The driver (and PowerDevil/UPower) can set its brightness, but nothing turns it off
after inactivity. This is a small root systemd service that does:

- after **30 seconds** with no keyboard/touchpad/touch-bar input, writes `0`;
- on the next input event (key, pointer, touch pad, or lid-open), restores the last
  non-zero brightness;
- preserves brightness changes made with the Touch Bar keys — it reads the current
  value when the timeout fires;
- restores the backlight when stopped, so `systemd-backlight` doesn't save `0` for
  the next boot.

It is independent of the Touch Bar driver: it only needs the `spi::kbd_backlight`
LED and works even if the Touch Bar is disabled.

## Install

```bash
sudo ./install.sh                 # 30 s
sudo ./install.sh --timeout=60    # different timeout
sudo ./install.sh --uninstall
./install.sh --check              # detect the LED and input devices, no root
```

The service starts immediately; no reboot is needed.

## Change the timeout

```bash
sudoedit /etc/default/kbd-backlight-timeout
sudo systemctl restart kbd-backlight-timeout.service
```

`KBD_BACKLIGHT_TIMEOUT=0` disables the timeout (the service exits; it is not
restarted).

## How it behaves

- **Any** input device wakes it, including an external keyboard/mouse and the Touch
  Bar's input device. A lid-open switch event also wakes it.
- It never grabs input devices, so normal input is unaffected.
- If the backlight is already off (brightness `0`) when the timeout fires, it does
  not treat that as a value to restore; it waits for activity and stays off.
- If something else changes the brightness while the service has it off (PowerDevil
  profile change, resume), the service adopts the new value and restarts its timer.
- At shutdown, the service restores the backlight before `systemd-backlight` saves
  the LED state, so the next boot starts with your normal brightness.

## Files

- `/usr/local/bin/kbd-backlight-timeout`
- `/etc/systemd/system/kbd-backlight-timeout.service`
- `/etc/default/kbd-backlight-timeout`

## Caveats

- Runs as root because `/dev/input/event*` and the LED `brightness` file are
  root-only.
- The timeout is wall-clock, not tied to the compositor's idle state; it will also
  turn the backlight off while a video is playing if there is no input.
