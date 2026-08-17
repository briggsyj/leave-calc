# leave-calc

A small desktop GUI for calculating annual leave usage. Enter hours-per-day
and number of days, and it computes total leave hours plus a split between
two leave types (default 80/20, adjustable via a slider).

Built with [Zig](https://ziglang.org/) and [raylib](https://www.raylib.com/)
(via [raylib-zig](https://github.com/raylib-zig/raylib-zig)).

## Requirements

- Zig 0.16.0

## Building

```sh
zig build        # build the executable (zig-out/bin/leave-calc)
zig build run    # build and launch the GUI
zig build test   # run the pure-logic unit tests (src/calc.zig)
```

### Cross-platform release builds

Prebuilt executables for Windows, macOS and Linux (amd64 + arm64 each) are
attached to every [GitHub Release](../../releases). To build them yourself:

```sh
zig build release-windows -Doptimize=ReleaseFast  # amd64 + arm64, from any host
zig build release-macos -Doptimize=ReleaseFast    # amd64 + arm64, from any host
zig build release -Doptimize=ReleaseFast           # native arch only (Linux needs a matching host)
```

Windows and macOS builds cross-compile cleanly from any host. Linux is the
exception: raylib links real X11/OpenGL system libraries there, so
`zig build release` only works when run on a matching-arch Linux host with
those dev packages installed (`libgl1-mesa-dev libx11-dev libxrandr-dev
libxinerama-dev libxi-dev libxcursor-dev` on Debian/Ubuntu) — see
`.github/workflows/ci.yml` for the exact matrix.

Output goes to `zig-out/release/<arch>-<os>/`.

## Project layout

- `src/calc.zig` — pure calculation/validation logic, unit-tested and free
  of any GUI dependencies.
- `src/main.zig` — raylib/raygui GUI shell around `calc.zig`.

## License

GPLv2 — see [LICENSE](LICENSE).
