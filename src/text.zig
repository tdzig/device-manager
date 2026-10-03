//! Shared text normalization used while materializing device lists.
//!
//! `clean_and_simplify` is a faithful port of the reference helper
//! (mtgo-labs/device-manager device.go): it collapses consecutive ASCII
//! spaces into one and drops *leading* spaces. A trailing space is kept —
//! the upstream doc comment says "trims leading/trailing" but the
//! upstream *code* keeps the trailing one; the code behavior is what the
//! ported device lists were generated against, so it wins here too.

const std = @import("std");

/// Comptime variant: returns a comptime-allocated slice, so device lists
/// can be materialized with the normalization applied at no runtime cost.
pub fn clean_and_simplify(comptime text: []const u8) []const u8 {
    return comptime blk: {
        @setEvalBranchQuota(10_000);
        var result: []const u8 = "";
        var prev_space = true;
        for (text) |ch| {
            if (ch == ' ') {
                if (!prev_space) {
                    result = result ++ " ";
                    prev_space = true;
                }
                continue;
            }
            result = result ++ &[_]u8{ch};
            prev_space = false;
        }
        break :blk result;
    };
}

/// Runtime variant into a caller-provided buffer. `out` must be at least
/// `text.len` bytes long; returns the written sub-slice.
pub fn clean_and_simplify_into(out: []u8, text: []const u8) []const u8 {
    var n: usize = 0;
    var prev_space = true;
    for (text) |ch| {
        if (ch == ' ') {
            if (!prev_space) {
                out[n] = ' ';
                n += 1;
                prev_space = true;
            }
            continue;
        }
        out[n] = ch;
        n += 1;
        prev_space = false;
    }
    return out[0..n];
}

test "clean_and_simplify: leading dropped, runs collapsed" {
    try std.testing.expectEqualStrings(
        "abc def",
        clean_and_simplify("   abc    def"),
    );
}

test "clean_and_simplify: trailing space kept (reference behavior)" {
    try std.testing.expectEqualStrings(
        "abc def ",
        clean_and_simplify("  abc   def  "),
    );
}

test "clean_and_simplify: comptime and runtime variants agree" {
    const cases = [_][]const u8{
        "  Samsung   SM-G998B ",
        "103C_53307F G=D",
        "Z97-PRO GAMER",
        "   ",
        "",
    };
    var buf: [64]u8 = undefined;
    inline for (cases) |c| {
        const comptime_result = clean_and_simplify(c);
        const runtime_result = clean_and_simplify_into(&buf, c);
        try std.testing.expectEqualStrings(comptime_result, runtime_result);
    }
}
