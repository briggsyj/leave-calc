//! Annual Leave Usage Calculator — GUI entry point.
//!
//! Renders a small form (hours/day, days) and, on Calculate, computes total
//! annual leave hours and an adjustable split between the two leave types
//! ("Leave Main" / "Leave Alt") using the pure functions in `calc.zig`. GUI
//! code stays a thin shell around that logic: all the arithmetic and
//! validation is unit-tested independently.

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const calc = @import("calc");

const window_width = 480;
const window_height = 440;

/// Display names for the two leave categories `calc.SplitResult` produces
/// (`.planned` / `.buffer` in the pure-logic layer are generic on purpose).
const leave_main_label = "Leave Main";
const leave_alt_label = "Leave Alt";

/// A plain system sans-serif, used instead of raylib's blocky bitmap default.
const sans_serif_font_path = "C:/Windows/Fonts/segoeui.ttf";

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

    /// Validate both fields and (re)compute the split, or set an error
    /// message describing the first problem found.
    fn calculate(self: *AppState) void {
        self.error_msg = null;
        self.result = null;

        const hours_text = currentText(&self.hours_buf);
        const days_text = currentText(&self.days_buf);

        if (hours_text.len == 0 or days_text.len == 0) {
            self.error_msg = "Enter both hours per day and number of days.";
            return;
        }

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
    const font: rl.Font = rl.loadFontEx(sans_serif_font_path, 26, null) catch
        (rl.getFontDefault() catch unreachable);
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
    const calc_btn = rl.Rectangle.init(30, 160, 130, 34);
    const reset_btn = rl.Rectangle.init(170, 160, 130, 34);
    const copy_btn = rl.Rectangle.init(310, 160, 140, 34);
    const ratio_slider = rl.Rectangle.init(190, 222, 220, 20);

    while (!rl.windowShouldClose()) {
        // --- Input handling ---------------------------------------------
        if (rg.textBox(hours_box, &state.hours_buf, state.hours_edit)) {
            state.hours_edit = !state.hours_edit;
        }
        if (rg.textBox(days_box, &state.days_buf, state.days_edit)) {
            state.days_edit = !state.days_edit;
        }

        if (rg.button(calc_btn, "Calculate")) {
            state.calculate();
        }
        if (rg.button(reset_btn, "Reset")) {
            state.reset();
        }
        if (rg.button(copy_btn, "Copy Results")) {
            if (state.result) |r| {
                const z = std.fmt.bufPrintZ(
                    &text_buf,
                    "Total: {d:.2}h  " ++ leave_main_label ++ ": {d:.2}h  " ++ leave_alt_label ++ ": {d:.2}h",
                    .{ r.total, r.planned, r.buffer },
                ) catch "";
                rl.setClipboardText(z);
                state.copied_flash = 1.5;
            }
        }

        var ratio_value = state.planned_ratio;
        _ = rg.slider(ratio_slider, "0%", "100%", &ratio_value, 0.0, 1.0);
        if (ratio_value != state.planned_ratio) {
            state.planned_ratio = ratio_value;
            if (state.result != null) state.calculate();
        }

        if (state.copied_flash > 0) state.copied_flash -= rl.getFrameTime();

        // --- Drawing -------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        drawText(font, "Annual Leave Usage Calculator", 30, 20, 20, .dark_gray);

        _ = rg.label(rl.Rectangle.init(30, 65, 150, 24), "Hours per day:");
        _ = rg.label(rl.Rectangle.init(30, 115, 150, 24), "Number of days:");

        const ratio_label = std.fmt.bufPrintZ(
            &text_buf,
            leave_main_label ++ " / " ++ leave_alt_label ++ " split: {d:.0}% / {d:.0}%",
            .{ state.planned_ratio * 100.0, (1.0 - state.planned_ratio) * 100.0 },
        ) catch leave_main_label ++ " / " ++ leave_alt_label ++ " split";
        drawText(font, ratio_label, 30, 248, 18, .dark_gray);

        rl.drawLine(30, 282, 450, 282, .light_gray);

        if (state.error_msg) |msg| {
            var err_buf: [96]u8 = undefined;
            const z = std.fmt.bufPrintZ(&err_buf, "{s}", .{msg}) catch "Invalid input.";
            drawText(font, z, 30, 300, 18, .red);
        } else if (state.result) |r| {
            var total_buf: [64]u8 = undefined;
            const total_text = std.fmt.bufPrintZ(&total_buf, "Total leave hours: {d:.2}", .{r.total}) catch "";
            drawText(font, total_text, 30, 300, 20, .black);

            var planned_buf: [64]u8 = undefined;
            const planned_text = std.fmt.bufPrintZ(
                &planned_buf,
                leave_main_label ++ " ({d:.0}%): {d:.2} h",
                .{ state.planned_ratio * 100.0, r.planned },
            ) catch "";
            drawText(font, planned_text, 30, 330, 20, .green);

            var buffer_buf: [64]u8 = undefined;
            const buffer_text = std.fmt.bufPrintZ(
                &buffer_buf,
                leave_alt_label ++ " ({d:.0}%): {d:.2} h",
                .{ (1.0 - state.planned_ratio) * 100.0, r.buffer },
            ) catch "";
            drawText(font, buffer_text, 30, 360, 20, .orange);

            if (state.copied_flash > 0) {
                drawText(font, "Copied to clipboard!", 30, 395, 16, .gray);
            }
        } else {
            drawText(font, "Enter values and press Calculate.", 30, 300, 18, .gray);
        }
    }
}

/// Thin wrapper so call sites read like `rl.drawText` but always use our
/// loaded sans-serif font instead of raylib's built-in bitmap font.
fn drawText(font: rl.Font, text: [:0]const u8, x: f32, y: f32, size: f32, color: rl.Color) void {
    rl.drawTextEx(font, text, rl.Vector2.init(x, y), size, 1.0, color);
}
