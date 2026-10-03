//! macOS device data — raw model identifiers (as `system_profiler`
//! reports them), macOS releases, and the identifier → human-readable
//! name mapping, all materialized at comptime.
//!
//! Faithful port of mtgo-labs/device-manager macos.go (order and
//! duplicates preserved: the raw list feeds a first-occurrence dedup,
//! so duplicates in it are intentional and consumed there).

const std = @import("std");
const text = @import("../text.zig");
const DeviceInfo = @import("mod.zig").DeviceInfo;

pub const raw_device_models = [_][]const u8{
    "MacBookPro16,4",
    "MacBookPro16,3",
    "MacBookPro16,2",
    "MacBookPro16,1",
    "MacBookPro15,4",
    "MacBookPro15,3",
    "MacBookPro15,2",
    "MacBookPro15,1",
    "MacBookPro14,3",
    "MacBookPro14,2",
    "MacBookPro14,1",
    "MacBookPro13,3",
    "MacBookPro13,2",
    "MacBookPro13,1",
    "MacBookPro12,1",
    "MacBookPro11,5",
    "MacBookPro11,4",
    "MacBookPro11,3",
    "MacBookPro11,2",
    "MacBookPro11,1",
    "MacBookPro10,2",
    "MacBookPro10,1",
    "MacBookAir9,1",
    "MacBookAir8,2",
    "MacBookAir8,1",
    "MacBookAir7,2",
    "MacBookAir7,2",
    "MacBookAir7,1",
    "MacBookAir6,2",
    "MacBookAir6,1",
    "MacBookAir6,2",
    "MacBook10,1",
    "MacBook9,1",
    "MacBook8,2",
    "MacBook8,1",
    "MacPro7,1",
    "MacPro6,1",
    "iMac20,2",
    "iMac20,1",
    "iMac19,1",
    "iMac18,3",
    "iMac18,2",
    "iMac18,1",
    "iMac17,1",
    "iMac17,1",
    "iMac17,1",
    "iMac16,2",
    "iMac16,1",
    "iMac15,2",
    "iMac15,1",
    "iMac14,4",
    "iMac14,3",
    "iMac14,2",
    "iMac14,1",
    "iMacPro1,1",
};

pub const system_versions = [_][]const u8{
    "macOS 10.12",
    "macOS 10.12.1",
    "macOS 10.12.2",
    "macOS 10.12.3",
    "macOS 10.12.4",
    "macOS 10.12.5",
    "macOS 10.12.6",
    "macOS 10.13",
    "macOS 10.13.1",
    "macOS 10.13.2",
    "macOS 10.13.3",
    "macOS 10.13.4",
    "macOS 10.13.5",
    "macOS 10.13.6",
    "macOS 10.14",
    "macOS 10.14.1",
    "macOS 10.14.2",
    "macOS 10.14.3",
    "macOS 10.14.4",
    "macOS 10.14.5",
    "macOS 10.14.6",
    "macOS 10.15",
    "macOS 10.15.1",
    "macOS 10.15.2",
    "macOS 10.15.3",
    "macOS 10.15.4",
    "macOS 10.15.5",
    "macOS 10.15.6",
    "macOS 10.15.7",
    "macOS 11.0",
    "macOS 11.0.1",
    "macOS 11.1",
    "macOS 11.2",
    "macOS 11.2.1",
    "macOS 11.2.2",
    "macOS 11.2.3",
    "macOS 11.3",
    "macOS 11.3.1",
    "macOS 11.4",
    "macOS 11.5",
    "macOS 11.5.1",
    "macOS 11.5.2",
    "macOS 11.6",
    "macOS 11.6.1",
    "macOS 11.6.2",
    "macOS 12.0",
    "macOS 12.0.1",
    "macOS 12.1",
};

/// Converts a model identifier (e.g. "MacBookPro16,4") to a
/// human-readable name (e.g. "MacBook Pro,"): strips digits, splits
/// words at capitals, joins with spaces except inside "MacBook".
/// Port of the reference `macOSFromIdentifier`, quirks included.
pub fn from_identifier(comptime model: []const u8) []const u8 {
    return comptime blk: {
        @setEvalBranchQuota(50_000);
        var words: []const []const u8 = &.{};
        var word: []const u8 = "";
        for (model) |ch| {
            if (ch >= '0' and ch <= '9') continue;
            if (ch >= 'A' and ch <= 'Z') {
                if (word.len != 0) {
                    words = words ++ &[_][]const u8{word};
                    word = "";
                }
            }
            word = word ++ &[_]u8{ch};
        }
        if (word.len != 0) words = words ++ &[_][]const u8{word};

        var result: []const u8 = "";
        for (words) |w| {
            if (result.len != 0 and !std.mem.eql(u8, w, "Mac") and !std.mem.eql(u8, w, "Book")) {
                result = result ++ " ";
            }
            result = result ++ w;
        }
        break :blk result;
    };
}

/// The deduplicated, human-readable model list (first occurrence wins),
/// normalized and materialized at comptime.
pub const device_models: []const []const u8 = blk: {
    @setEvalBranchQuota(200_000);
    var list: []const []const u8 = &.{};
    outer: for (raw_device_models) |m| {
        const name = text.clean_and_simplify(from_identifier(m));
        for (list) |existing| {
            if (std.mem.eql(u8, existing, name)) continue :outer;
        }
        list = list ++ &[_][]const u8{name};
    }
    break :blk list;
};

test "identifier to human-readable name" {
    try std.testing.expectEqualStrings("MacBook Pro,", from_identifier("MacBookPro16,4"));
    try std.testing.expectEqualStrings("MacBook Air,", from_identifier("MacBookAir8,1"));
    try std.testing.expectEqualStrings("Mac Pro,", from_identifier("MacPro6,1"));
    // The reference word-splitter treats the capital in "iMac" as a
    // word boundary, and the joiner only skips the space for the exact
    // words "Mac"/"Book": "iMac" keeps "Mac," glued (comma makes it a
    // different word) while iMacPro splits after "Mac". The trailing
    // comma (from the identifier's ",<board>") survives too. Ported
    // as-is.
    try std.testing.expectEqualStrings("i Mac,", from_identifier("iMac20,2"));
    try std.testing.expectEqualStrings("iMac Pro,", from_identifier("iMacPro1,1"));
}

test "dedup keeps first occurrence only" {
    // "MacBookAir7,2" and "iMac17,1" appear more than once upstream.
    var macbook_air_7_2: usize = 0;
    var imac_17_1: usize = 0;
    for (device_models) |m| {
        if (std.mem.eql(u8, m, "MacBook Air,")) macbook_air_7_2 += 1;
        if (std.mem.eql(u8, m, "i Mac,")) imac_17_1 += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), macbook_air_7_2);
    try std.testing.expectEqual(@as(usize, 1), imac_17_1);
    try std.testing.expect(device_models.len < raw_device_models.len);
    try std.testing.expect(system_versions.len == 48);
}
