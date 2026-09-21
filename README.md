# Pdok — the side notch

A side-anchored dashboard for [Omarchy](https://omarchy.org)'s shell, inspired
by [ruixen-shell](https://github.com/gitcoder89431/ruixen-shell)'s notch —
same idea (everything in one summoned surface) but living on the **edge of
the screen** instead of dropping from the top-center: a full-height drawer
that hugs the right (or left) side below the bar.

![preview](preview.png)

## What's inside

| Tab | Shows |
|---|---|
| **Dash** | CPU / memory / disk / battery bars, uptime, network throughput |
| **Media** | Now-playing with art, progress, and play/pause/next/previous (MPRIS) |
| **Notifications** | Notification history from Omarchy's own notification store, with unread tracking and mark-all-read |

Details:

- The drawer follows your theme (colors, fonts, radii, popup translucency)
  through the shell's own tokens.
- Media routes through the first-party `omarchy.media` service when enabled
  (preferred-player logic + OSD feedback) and falls back to direct MPRIS.
  The seek bar supports click/drag seeking; positions longer than an hour
  render as h:mm:ss. Note: bare `mpv` publishes no MPRIS interface — use an
  MPRIS bridge (e.g. mpv-mpris) for it to appear here. Album art is only
  shown for local `file://` art — never fetched over the network from the
  shell process.
- The bar button shows a red dot while there are unread notifications, and
  its glyph mirrors the configured side. Clicking an unread entry marks
  just that entry read; the Mark read button (or everything-before mark)
  clears in bulk. Read flags live in `~/.local/state/omarchy/pdok.json`.
- Notification bodies are normalized to plain text at read time — HTML
  entities decoded, `<br>` tags and literal `\n` sequences turned into real
  line breaks, remaining tags stripped — and always rendered as plain text.
- Metrics are sampled once per shell in a shared service (`/proc` + `df`),
  not per monitor.

## Install

From a git clone of this repo:

```bash
omarchy plugin add https://github.com/Palccod/Pdok.git --enable
```

Or from a local folder: symlink/copy it to
`~/.config/omarchy/plugins/palccod.pdok`, then enable it from
**Omarchy settings → Bar widgets** (it lands in the right section) and
restart the shell.

## Use

- **Click the bar button** (outlined card with a filled strip) to toggle the drawer.
- **Right-click the button** to flip the drawer between the right and left edge.
- Escape or clicking anywhere outside closes it. Tab / Shift+Tab move between
  bar widgets' panels, like any Omarchy popout.

### Settings

Per-widget settings live in the `palccod.pdok` entry under `bar.layout` in
`~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `side` | `right` | Which screen edge the drawer hugs (`left` or `right`) — also set by right-clicking the bar button |
| `width` | `400` | Drawer width in px (clamped 280–640) |

### IPC

```bash
omarchy-shell palccod.pdok toggle          # open/close/show/hide/toggle
omarchy-shell palccod.pdok setTab media    # dash | media | notifications (opens the drawer)
omarchy-shell palccod.pdok setSide left    # right | left
omarchy-shell palccod.pdok markRead        # mark all notifications read
omarchy-shell palccod.pdok state           # JSON dump for scripting
```

Read/unread state is stored in `~/.local/state/omarchy/pdok.json`; the
notification list itself is read (read-only) from Omarchy's
`~/.local/state/omarchy/notifications/history/`.

## Uninstall

```bash
omarchy plugin remove palccod.pdok --yes
```

## License

MIT. Concept credit: ruixen-shell's `ruixen.notch`.
