//! Device data: the platform model/version tables the deterministic
//! generator picks from, ported from mtgo-labs/device-manager.
//!
//! Every list is a `const` slice — either converted verbatim from the
//! upstream Go literals (android, desktop: order and duplicates
//! preserved, because selection indexes by position) or materialized at
//! comptime from smaller tables (ios, macos, linux) with the upstream
//! expansion logic. Nothing lazily initializes; there is no runtime
//! state in this package.

/// A device model paired with the OS version it runs.
pub const DeviceInfo = struct {
    model: []const u8,
    version: []const u8,
};

pub const android = @import("android.zig");
pub const desktop = @import("desktop.zig");
pub const ios = @import("ios.zig");
pub const macos = @import("macos.zig");
pub const linux = @import("linux.zig");
pub const desktop_clean = @import("desktop_clean.zig");

test "android data sanity" {
    try @import("std").testing.expect(android.device_models.len == 4870);
    try @import("std").testing.expect(android.system_versions.len == 9);
    try @import("std").testing.expectEqualStrings("Samsung GT-I5510M", android.device_models[0]);
    try @import("std").testing.expectEqualStrings("Xiaomi MIBOX3", android.device_models[android.device_models.len - 1]);
}

test "desktop data sanity" {
    try @import("std").testing.expect(desktop.general_device_models.len == 790);
    try @import("std").testing.expectEqualStrings("Windows 11", desktop.windows_system_versions[0]);
    try @import("std").testing.expectEqualStrings("Windows 10", desktop.windows_system_versions[1]);
    try @import("std").testing.expectEqualStrings("Windows 7", desktop.windows_system_versions[desktop.windows_system_versions.len - 1]);
    try @import("std").testing.expectEqual(@as(usize, 5), desktop.windows_system_versions.len);
}

test {
    // Collect inline tests from the materialized-data modules.
    _ = @import("ios.zig");
    _ = @import("macos.zig");
    _ = @import("linux.zig");
    _ = @import("desktop_clean.zig");
}
