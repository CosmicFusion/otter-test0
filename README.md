# otter-examples

Starter templates for [Otter Shell](https://git.pika-os.com/otter-shell) Wayland apps. The UI uses **Surface Description** (SD): you build declarative `SurfaceNode` trees instead of hand-writing draw commands.

**Guides** (open in a browser):

| Guide | Best for |
|-------|----------|
| [`docs/build-your-first-app.html`](docs/build-your-first-app.html) | Hands-on: run it, click things, add a button |
| [`docs/creating-wayland-apps.html`](docs/creating-wayland-apps.html) | Reading what each source file does |

Both modes show the same card: themed panel, Otter logo, counter label, and increment button with hover cursor and press feedback.

**Window mode only:** SD inspector and FPS overlay (`--inspect`, `--metrics`, or **Ctrl+Shift+I**).

## Try it

| Command | Shell | What you get |
|---------|-------|--------------|
| `zig build -Doptimize=ReleaseFast run -- layer` | `zwlr_layer_shell_v1` | Small overlay, top-right |
| `zig build -Doptimize=ReleaseFast run -- window` | `xdg_shell` | Normal desktop window |

## Where things live

```
src/
  main.zig              CLI entry
  ui/
    demo.zig            card state, SD tree, pointer input, cursor, damage helpers
    draw.zig            emit, repair, rasterize
  shell/
    frame.zig           wl_surface.frame batching
    layer_app.zig       layer-shell lifecycle
    xdg_app.zig         XDG toplevel lifecycle
```

**Add a button?** Edit `ui/demo.zig`: node in `buildCard()`, click handler in `onPointerPress()`, release in `onPointerRelease()` if you want press feedback.

`ui/` is shell-agnostic. `shell/` is Wayland glue (forwards pointer events, calls `applyPointerCursor()`).

## Damage tracking

1. **Idle:** `poll(-1)` blocks until Wayland has work.
2. **Frame callback:** `shell/frame.zig` batches dirty flags into one paint per refresh.
3. **Partial damage:** hover, press, and release repaint only the button or counter rects that changed.
4. **Full damage:** first configure, resize, HiDPI scale change, or when a debug overlay is on.

## Dependencies

Pinned to `v0.11.34` in `build.zig.zon`: `otter-ui`, `otter-wayland`, `otter-render`, `otter-theme`, `otter-geo`, `otter-utils`.

## Build

```bash
cd otter-examples
zig build -Doptimize=ReleaseFast test
zig build -Doptimize=ReleaseFast run -- window
zig build -Doptimize=ReleaseFast run -- layer
```

Use `ReleaseFast`. Debug builds of the full UI tree can segfault during compile in this monorepo.
