//! Annual Leave Usage Calculator — GUI entry point.
//!
//! Renders a small form (hours/day, days) that recomputes an adjustable
//! split between two leave shares live, as soon as both fields hold valid
//! input, using the pure functions in `calc.zig`. GUI code stays a thin
//! shell around that logic: all the arithmetic and validation is
//! unit-tested independently.

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const calc = @import("calc");

const window_width = 480;
const window_height = 440;

/// Plain system sans-serif candidates, used instead of raylib's blocky
/// bitmap default. Tried in order per-platform; the first one that loads
/// wins, with raylib's built-in font as the final fallback.
const sans_serif_font_paths: []const [:0]const u8 = switch (@import("builtin").os.tag) {
    .windows => &.{"C:/Windows/Fonts/segoeui.ttf"},
    .macos => &.{
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    },
    else => &.{
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    },
};

/// Try each candidate system font path in turn, returning the first that
/// loads successfully, or raylib's built-in default font otherwise.
fn loadSansSerifFont() rl.Font {
    for (sans_serif_font_paths) |path| {
        if (rl.loadFontEx(path, 26, null)) |font| {
            return font;
        } else |_| {}
    }
    return rl.getFontDefault() catch unreachable;
}

/// Fixed-capacity text buffer backing raygui's editable text boxes.
/// raygui edits this in place as a null-terminated C string.
const TextBuf = [32:0]u8;

fn zeroed() TextBuf {
    return std.mem.zeroes(TextBuf);
}

/// Build a zero-padded text buffer pre-filled with a comptime-known string,
/// used for the "hours per day" field's default value.
fn textBufFrom(comptime text: []const u8) TextBuf {
    var buf: TextBuf = std.mem.zeroes(TextBuf);
    @memcpy(buf[0..text.len], text);
    return buf;
}

fn currentText(buf: *const TextBuf) []const u8 {
    return std.mem.sliceTo(buf, 0);
}

/// UI/application state, separate from the pure calc.zig logic.
const AppState = struct {
    hours_buf: TextBuf = textBufFrom("7.25"),
    days_buf: TextBuf = zeroed(),
    hours_edit: bool = false,
    days_edit: bool = false,

    /// Leave Main's share of the 80/20 (or user-adjusted) split, in [0, 1].
    planned_ratio: f32 = @floatCast(calc.default_planned_ratio),

    result: ?calc.SplitResult = null,
    error_msg: ?[]const u8 = null,
    copied_flash: f32 = 0,

    fn reset(self: *AppState) void {
        self.* = .{};
    }

    /// Validate both fields (assumed non-empty; see the caller in `main`)
    /// and (re)compute the split, or set an error message describing the
    /// first problem found.
    fn calculate(self: *AppState) void {
        self.error_msg = null;
        self.result = null;

        const hours_text = currentText(&self.hours_buf);
        const days_text = currentText(&self.days_buf);

        const hours = calc.parsePositive(hours_text) catch |err| {
            self.error_msg = switch (err) {
                calc.InputError.NotANumber => "Hours per day must be a positive number.",
                calc.InputError.NonPositive => "Hours per day must be greater than zero.",
            };
            return;
        };
        const days = calc.parsePositive(days_text) catch |err| {
            self.error_msg = switch (err) {
                calc.InputError.NotANumber => "Number of days must be a positive number.",
                calc.InputError.NonPositive => "Number of days must be greater than zero.",
            };
            return;
        };

        self.result = calc.calculate(hours, days, self.planned_ratio);
    }
};

pub fn main() anyerror!void {
    rl.initWindow(window_width, window_height, "Annual Leave Usage Calculator");
    defer rl.closeWindow();
    rl.setWindowMinSize(window_width, window_height);
    rl.setTargetFPS(60);

    // Load a basic system sans-serif for a cleaner look than raylib's
    // built-in bitmap font; fall back to the default if unavailable. Baked
    // close to our actual on-screen text sizes (16-20px) so it isn't
    // minified so hard that it turns blurry/sub-pixel.
    const font: rl.Font = loadSansSerifFont();
    defer if (rl.isFontValid(font)) rl.unloadFont(font);
    rl.setTextureFilter(font.texture, .bilinear);
    rg.setFont(font);
    // raygui's own default text size (~10px) would otherwise stretch our
    // much-larger atlas down hard; match it to the rest of the UI.
    rg.setStyle(.default, .text_size, 18);

    var state = AppState{};

    var text_buf: [96]u8 = undefined;

    // Static layout — laid out once, referenced every frame.
    const hours_box = rl.Rectangle.init(190, 60, 220, 30);
    const days_box = rl.Rectangle.init(190, 110, 220, 30);
    const reset_btn = rl.Rectangle.init(30, 160, 130, 34);
    const ratio_slider = rl.Rectangle.init(190, 222, 220, 20);
    const planned_box = rl.Rectangle.init(30, 278, 195, 36);
    const buffer_box = rl.Rectangle.init(235, 278, 195, 36);
    const copy_btn = rl.Rectangle.init(30, 328, 170, 34);

    while (!rl.windowShouldClose()) {
        // --- Input handling ---------------------------------------------
        if (rg.textBox(hours_box, &state.hours_buf, state.hours_edit)) {
            state.hours_edit = !state.hours_edit;
        }
        if (rg.textBox(days_box, &state.days_buf, state.days_edit)) {
            state.days_edit = !state.days_edit;
        }

        if (rg.button(reset_btn, "Reset")) {
            state.reset();
        }

        var ratio_value = state.planned_ratio;
        var left_pct_buf: [8:0]u8 = undefined;
        var right_pct_buf: [8:0]u8 = undefined;
        const left_pct = std.fmt.bufPrintZ(&left_pct_buf, "{d:.0}%", .{state.planned_ratio * 100.0}) catch "";
        const right_pct = std.fmt.bufPrintZ(&right_pct_buf, "{d:.0}%", .{(1.0 - state.planned_ratio) * 100.0}) catch "";
        _ = rg.slider(ratio_slider, left_pct, right_pct, &ratio_value, 0.0, 1.0);
        state.planned_ratio = ratio_value;

        // Recompute live: as soon as both fields hold something, and every
        // time either they or the split slider change.
        if (currentText(&state.hours_buf).len > 0 and currentText(&state.days_buf).len > 0) {
            state.calculate();
        } else {
            state.result = null;
            state.error_msg = null;
        }

        if (state.copied_flash > 0) state.copied_flash -= rl.getFrameTime();

        // --- Drawing -------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        drawText(font, "Annual Leave Usage Calculator", 30, 20, 20, .dark_gray);

        _ = rg.label(rl.Rectangle.init(30, 65, 150, 24), "Hours per day:");
        _ = rg.label(rl.Rectangle.init(30, 115, 150, 24), "Number of days:");

        rl.drawLine(30, 260, 450, 260, .light_gray);

        if (state.error_msg) |msg| {
            var err_buf: [96]u8 = undefined;
            const z = std.fmt.bufPrintZ(&err_buf, "{s}", .{msg}) catch "Invalid input.";
            drawText(font, z, 30, 278, 18, .red);
        } else if (state.result) |r| {
            const planned_pct = state.planned_ratio * 100.0;
            const buffer_pct = (1.0 - state.planned_ratio) * 100.0;

            rl.drawRectangleLinesEx(planned_box, 1, .gray);
            var planned_buf: [64]u8 = undefined;
            const planned_text = std.fmt.bufPrintZ(&planned_buf, "{d:.2} h", .{r.planned}) catch "";
            drawText(font, planned_text, planned_box.x + 12, planned_box.y + 8, 20, .gray);

            rl.drawRectangleLinesEx(buffer_box, 1, .gray);
            var buffer_buf: [64]u8 = undefined;
            const buffer_text = std.fmt.bufPrintZ(&buffer_buf, "{d:.2} h", .{r.buffer}) catch "";
            drawText(font, buffer_text, buffer_box.x + 12, buffer_box.y + 8, 20, .gray);

            if (rg.button(copy_btn, "Copy Results")) {
                const z = std.fmt.bufPrintZ(
                    &text_buf,
                    "total_hours,{d:.0}%_hours,{d:.0}%_hours\n{d:.2},{d:.2},{d:.2}",
                    .{ planned_pct, buffer_pct, r.total, r.planned, r.buffer },
                ) catch "";
                rl.setClipboardText(z);
                state.copied_flash = 1.5;
            }

            if (state.copied_flash > 0) {
                drawText(font, "Copied to clipboard!", copy_btn.x + copy_btn.width + 15, copy_btn.y + 9, 16, .gray);
            }
        } else {
            drawText(font, "Enter hours per day and number of days above.", 30, 278, 18, .gray);
        }
    }
}

/// Thin wrapper so call sites read like `rl.drawText` but always use our
/// loaded sans-serif font instead of raylib's built-in bitmap font.
fn drawText(font: rl.Font, text: [:0]const u8, x: f32, y: f32, size: f32, color: rl.Color) void {
    rl.drawTextEx(font, text, rl.Vector2.init(x, y), size, 1.0, color);
}
