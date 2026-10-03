//! Linux device data — the desktop-environment × display-protocol ×
//! glibc cross product, materialized at comptime.
//!
//! Faithful port of mtgo-labs/device-manager linux.go (84 entries).

const std = @import("std");

const desktop_environments = [_][]const u8{ "GNOME", "MATE", "XFCE", "Cinnamon", "Unity", "ubuntu", "LXDE" };
const display_protocols = [_][]const u8{ "Wayland", "XWayland", "X11" };
const glibc_versions = [_][]const u8{ "2.31", "2.32", "2.33", "2.34" };

/// `"Linux <env> <protocol> glibc <version>"` strings in cross-product
/// order (env outer, protocol middle, glibc inner) — same order the
/// reference builds at init time.
pub const system_versions: []const []const u8 = blk: {
    @setEvalBranchQuota(10_000);
    var list: []const []const u8 = &.{};
    for (desktop_environments) |env| {
        for (display_protocols) |protocol| {
            for (glibc_versions) |glibc| {
                list = list ++ &[_][]const u8{
                    "Linux " ++ env ++ " " ++ protocol ++ " glibc " ++ glibc,
                };
            }
        }
    }
    break :blk list;
};

test "cross product size and shape" {
    try std.testing.expectEqual(@as(usize, 7 * 3 * 4), system_versions.len);
    try std.testing.expectEqualStrings("Linux GNOME Wayland glibc 2.31", system_versions[0]);
    try std.testing.expectEqualStrings("Linux GNOME Wayland glibc 2.32", system_versions[1]);
    try std.testing.expectEqualStrings("Linux GNOME XWayland glibc 2.31", system_versions[4]);
    try std.testing.expectEqualStrings("Linux LXDE X11 glibc 2.34", system_versions[system_versions.len - 1]);
    for (system_versions) |v| {
        try std.testing.expect(std.mem.startsWith(u8, v, "Linux "));
        try std.testing.expect(std.mem.indexOf(u8, v, " glibc ") != null);
    }
}
