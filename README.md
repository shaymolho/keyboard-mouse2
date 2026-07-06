# Keyboard Mouse

A tiny macOS menu bar app that controls the mouse pointer from the keyboard.

| Hotkey | Action |
| --- | --- |
| ⌃⌥ arrow keys | Move the pointer (hold to accelerate; two arrows = diagonal) |
| ⌃⌥ S | Left click |
| ⌃⌥ A | Right click |

Movement starts slow for precision and ramps up to full speed over ~1 second of
holding. Releasing all arrows resets the ramp. The hotkeys are swallowed, so
the app in front never sees them; all other keys pass through untouched.

The menu bar icon (cursor with rays) has an **Enabled** toggle and **Quit**.

## Build & run

```sh
swift build
.build/debug/KeyboardMouse
```

On first launch macOS prompts for **Accessibility** permission (the app needs
it to observe and suppress keyboard events and to post mouse events). Grant it
in System Settings → Privacy & Security → Accessibility — the app picks it up
within a couple of seconds, no relaunch needed.

## Permission gotchas

- Run the built binary directly (`.build/debug/KeyboardMouse`), **not**
  `swift run` — the Accessibility grant attaches to the executable that owns
  the event tap, and `.build/debug/KeyboardMouse` is a stable path.
- macOS ties the grant to the binary's code signature, and SPM re-signs
  (ad-hoc) on every build. If hotkeys are dead after a rebuild, toggle the
  KeyboardMouse entry off and on in System Settings → Accessibility (or remove
  and re-add it).
- Optional fix for frequent rebuilds: sign with a stable identity after each
  build, e.g. `codesign --force --sign "Apple Development" .build/debug/KeyboardMouse`.
