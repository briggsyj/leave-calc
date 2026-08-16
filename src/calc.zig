//! Pure leave-calculation logic, decoupled from any GUI code so it can be
//! exercised with `zig test` independent of raylib/zgui.

const std = @import("std");

/// Result of splitting a total number of leave hours into a "planned" and
/// "buffer" portion according to some ratio (default 80/20).
pub const SplitResult = struct {
    total: f64,
    planned: f64,
    buffer: f64,
};

/// Errors that can occur while validating raw user input.
pub const InputError = error{
    NotANumber,
    NonPositive,
};

/// Default split ratio: 80% planned leave / 20% buffer.
pub const default_planned_ratio: f64 = 0.8;

/// Multiply hours-per-day by number-of-days to get total annual leave hours.
pub fn totalHours(hours_per_day: f64, days: f64) f64 {
    return hours_per_day * days;
}

/// Split `total` hours into a planned/buffer pair using `planned_ratio`
/// (e.g. 0.8 for an 80/20 split). `planned_ratio` is expected to be in
/// [0, 1]; the remainder is treated as the buffer share.
pub fn split(total: f64, planned_ratio: f64) SplitResult {
    const planned = total * planned_ratio;
    const buffer = total - planned;
    return .{ .total = total, .planned = planned, .buffer = buffer };
}

/// Convenience wrapper: compute total hours and the 80/20 split in one call.
pub fn calculate(hours_per_day: f64, days: f64, planned_ratio: f64) SplitResult {
    return split(totalHours(hours_per_day, days), planned_ratio);
}

/// Validate a raw numeric input: must be finite, not NaN, and strictly
/// positive. Used for both "hours per day" and "number of days" fields.
pub fn validatePositive(value: f64) InputError!f64 {
    if (std.math.isNan(value) or !std.math.isFinite(value)) {
        return InputError.NotANumber;
    }
    if (value <= 0) {
        return InputError.NonPositive;
    }
    return value;
}

/// Parse a raw text field (e.g. straight from a GUI text box) into a
/// validated positive f64. Empty/whitespace-only input and unparsable text
/// both surface as `InputError.NotANumber`.
pub fn parsePositive(text: []const u8) InputError!f64 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return InputError.NotANumber;
    const value = std.fmt.parseFloat(f64, trimmed) catch return InputError.NotANumber;
    return validatePositive(value);
}

/// Round a value to `places` decimal places (0, 1, or 2 are the practical
/// range for this app's output display).
pub fn roundTo(value: f64, places: u32) f64 {
    const factor = std.math.pow(f64, 10.0, @floatFromInt(places));
    return @round(value * factor) / factor;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "totalHours multiplies hours by days" {
    try testing.expectApproxEqAbs(@as(f64, 152.0), totalHours(7.6, 20), 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 0.0), totalHours(7.6, 0), 1e-9);
}

test "split divides total into planned/buffer using ratio" {
    const result = split(152.0, default_planned_ratio);
    try testing.expectApproxEqAbs(@as(f64, 152.0), result.total, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 121.6), result.planned, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 30.4), result.buffer, 1e-9);
}

test "split planned + buffer always reconstitutes total" {
    const ratios = [_]f64{ 0.0, 0.2, 0.5, 0.8, 1.0 };
    for (ratios) |ratio| {
        const result = split(200.0, ratio);
        try testing.expectApproxEqAbs(result.total, result.planned + result.buffer, 1e-9);
    }
}

test "calculate combines totalHours and split" {
    const result = calculate(8.0, 25.0, default_planned_ratio);
    try testing.expectApproxEqAbs(@as(f64, 200.0), result.total, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 160.0), result.planned, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 40.0), result.buffer, 1e-9);
}

test "validatePositive accepts positive finite values" {
    try testing.expectEqual(@as(f64, 7.6), try validatePositive(7.6));
}

test "validatePositive rejects zero and negative values" {
    try testing.expectError(InputError.NonPositive, validatePositive(0));
    try testing.expectError(InputError.NonPositive, validatePositive(-5));
}

test "validatePositive rejects NaN and infinity" {
    try testing.expectError(InputError.NotANumber, validatePositive(std.math.nan(f64)));
    try testing.expectError(InputError.NotANumber, validatePositive(std.math.inf(f64)));
}

test "parsePositive parses valid numeric text" {
    try testing.expectApproxEqAbs(@as(f64, 7.6), try parsePositive("7.6"), 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 20.0), try parsePositive("  20 "), 1e-9);
}

test "parsePositive rejects empty, non-numeric, and non-positive text" {
    try testing.expectError(InputError.NotANumber, parsePositive(""));
    try testing.expectError(InputError.NotANumber, parsePositive("   "));
    try testing.expectError(InputError.NotANumber, parsePositive("abc"));
    try testing.expectError(InputError.NonPositive, parsePositive("-3"));
    try testing.expectError(InputError.NonPositive, parsePositive("0"));
}

test "roundTo rounds to requested decimal places" {
    try testing.expectApproxEqAbs(@as(f64, 121.6), roundTo(121.6, 1), 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 121.57), roundTo(121.567, 2), 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 122.0), roundTo(121.567, 0), 1e-9);
}
