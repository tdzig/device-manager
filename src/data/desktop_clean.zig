//! Derived desktop data: `general_device_models` with whitespace
//! normalized (leading spaces dropped, runs collapsed — see `text.zig`),
//! shared by the Windows and Linux selection paths. Computed at
//! comptime; port of the reference `cleanedDesktopModels`.

const std = @import("std");
const text = @import("../text.zig");
const desktop = @import("desktop.zig");

pub const cleaned_models: []const []const u8 = blk: {
    @setEvalBranchQuota(1_000_000);
    var list: []const []const u8 = &.{};
    for (desktop.general_device_models) |m| {
        list = list ++ &[_][]const u8{text.clean_and_simplify(m)};
    }
    break :blk list;
};

test "cleaned models keep count and lose leading spaces" {
    try std.testing.expectEqual(desktop.general_device_models.len, cleaned_models.len);
    for (cleaned_models) |m| {
        try std.testing.expect(m.len == 0 or m[0] != ' ');
    }
}

test "normalization is a no-op on the ported data" {
    // The upstream list carries no irregular whitespace (checked
    // against the source: no leading/doubled spaces), so the reference
    // pass — kept for parity — leaves every model unchanged.
    for (desktop.general_device_models, cleaned_models) |raw, clean| {
        try std.testing.expectEqualStrings(raw, clean);
    }
}
