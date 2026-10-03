//! iOS device data — iPhone model/suffix table and per-major system
//! versions, expanded at comptime into the flat model×version list the
//! deterministic selection indexes.
//!
//! Faithful port of mtgo-labs/device-manager ios.go. One deliberate
//! difference: the reference iterates its minor-version map with Go's
//! randomized map order (its own list order varies run to run); this
//! port walks the table in source order, so iOS generation is fully
//! deterministic here.

const std = @import("std");
const DeviceInfo = @import("mod.zig").DeviceInfo;

/// Model families: generation number + sold suffixes (`""` = plain).
pub const Model = struct {
    id: u8,
    suffixes: []const []const u8,
};

pub const device_models = [_]Model{
    .{ .id = 5, .suffixes = &.{"S"} },
    .{ .id = 6, .suffixes = &.{ " Plus", "", "S", "S Plus" } },
    .{ .id = 7, .suffixes = &.{ "", " Plus" } },
    .{ .id = 8, .suffixes = &.{ "", " Plus" } },
    .{ .id = 10, .suffixes = &.{ "", "S", "S Max", "R" } },
    .{ .id = 11, .suffixes = &.{ "", " Pro", " Pro Max" } },
    .{ .id = 12, .suffixes = &.{ " mini", "", " Pro", " Pro Max" } },
    .{ .id = 13, .suffixes = &.{ " Pro", " Pro Max", " Mini", "" } },
};

/// One minor release; `patches == null` means the bare `major.minor`.
pub const Minor = struct {
    minor: u8,
    patches: ?[]const []const u8 = null,
};

pub const Major = struct {
    major: u8,
    minors: []const Minor,
};

/// System versions by major, in source order (see module doc).
pub const system_versions = [_]Major{
    .{ .major = 15, .minors = &.{
        .{ .minor = 2 },
        .{ .minor = 1, .patches = &.{"1"} },
        .{ .minor = 0, .patches = &.{ "2", "1" } },
    } },
    .{ .major = 14, .minors = &.{
        .{ .minor = 8, .patches = &.{"1"} },
        .{ .minor = 7, .patches = &.{"1"} },
        .{ .minor = 6 },
        .{ .minor = 5, .patches = &.{"1"} },
        .{ .minor = 4, .patches = &.{ "2", "1" } },
        .{ .minor = 3 },
        .{ .minor = 2, .patches = &.{"1"} },
        .{ .minor = 1 },
        .{ .minor = 0, .patches = &.{"1"} },
    } },
    .{ .major = 13, .minors = &.{
        .{ .minor = 7 },
        .{ .minor = 6, .patches = &.{"1"} },
        .{ .minor = 5, .patches = &.{"1"} },
        .{ .minor = 4, .patches = &.{"1"} },
        .{ .minor = 3, .patches = &.{"1"} },
        .{ .minor = 2, .patches = &.{ "3", "2" } },
        .{ .minor = 1, .patches = &.{ "3", "2", "1" } },
    } },
    .{ .major = 12, .minors = &.{
        .{ .minor = 5, .patches = &.{ "5", "4", "3", "2", "1" } },
        .{ .minor = 4, .patches = &.{ "9", "8", "7", "6", "5", "4", "3", "2", "1" } },
        .{ .minor = 3, .patches = &.{ "2", "1" } },
        .{ .minor = 11, .patches = &.{"0"} },
        .{ .minor = 2 },
        .{ .minor = 1, .patches = &.{ "4", "3", "2", "1" } },
        .{ .minor = 0, .patches = &.{"1"} },
    } },
};

/// Majors a given iPhone generation can run (reference
/// `iosAvailableVersions`); model 10 is the iPhone X line.
fn available_majors(comptime id: u8) []const u8 {
    return switch (id) {
        13 => &[_]u8{15},
        12 => &[_]u8{ 14, 15 },
        11 => &[_]u8{ 13, 14, 15 },
        10 => &[_]u8{ 12, 13, 14, 15 },
        5 => &[_]u8{12},
        else => &[_]u8{ 12, 13, 14, 15 },
    };
}

fn major_entry(comptime major: u8) ?Major {
    for (system_versions) |e| {
        if (e.major == major) return e;
    }
    return null;
}

fn model_name(comptime id: u8, comptime suffix: []const u8) []const u8 {
    if (id == 10) return "iPhone X" ++ suffix;
    return std.fmt.comptimePrint("iPhone {d}{s}", .{ id, suffix });
}

/// The flat model×version list, materialized at comptime (the reference
/// builds it once lazily under a `sync.Once`).
pub const device_list: []const DeviceInfo = blk: {
    @setEvalBranchQuota(500_000);
    var list: []const DeviceInfo = &.{};
    for (device_models) |entry| {
        for (entry.suffixes) |suffix| {
            const model = model_name(entry.id, suffix);
            for (available_majors(entry.id)) |major| {
                const me = major_entry(major) orelse continue;
                for (me.minors) |m| {
                    if (m.patches) |patches| {
                        for (patches) |p| {
                            list = list ++ &[_]DeviceInfo{.{
                                .model = model,
                                .version = std.fmt.comptimePrint("{d}.{d}.{s}", .{ major, m.minor, p }),
                            }};
                        }
                    } else {
                        list = list ++ &[_]DeviceInfo{.{
                            .model = model,
                            .version = std.fmt.comptimePrint("{d}.{d}", .{ major, m.minor }),
                        }};
                    }
                }
            }
        }
    }
    break :blk list;
};

test "expansion covers every model family" {
    // One representative model string per generation (iPhone X for 10).
    const expected_prefixes = [_][]const u8{
        "iPhone 5S", "iPhone 6",  "iPhone 7",  "iPhone 8", "iPhone X",
        "iPhone 11", "iPhone 12", "iPhone 13",
    };
    for (expected_prefixes) |prefix| {
        var found = false;
        for (device_list) |info| {
            if (std.mem.startsWith(u8, info.model, prefix)) {
                found = true;
                break;
            }
        }
        if (!found) return error.MissingModelFamily;
    }
}

test "versions are major.minor[.patch] within supported majors" {
    for (device_list) |info| {
        var it = std.mem.splitScalar(u8, info.version, '.');
        var parts: usize = 0;
        var major: u16 = 0;
        while (it.next()) |part| {
            const n = std.fmt.parseInt(u16, part, 10) catch return error.BadVersion;
            if (parts == 0) major = n;
            parts += 1;
        }
        if (parts < 2 or parts > 3) return error.BadVersion;
        if (major < 12 or major > 15) return error.BadMajor;
    }
}
