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

## Project layout

- `src/calc.zig` — pure calculation/validation logic, unit-tested and free
  of any GUI dependencies.
- `src/main.zig` — raylib/raygui GUI shell around `calc.zig`.

## License

GPLv2 — see [LICENSE](LICENSE).
