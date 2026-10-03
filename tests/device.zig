//! Integration tests: reference parity and the td wire bridge.
//!
//! The parity goldens below were computed independently (Python,
//! straight from the upstream Go source lists and the documented
//! selection math: SHA-1(id)[0..8] big-endian mod 10^12; model =
//! list[h % len], version = list[(h / len) % len]). If this port's
//! lists or math drift from the reference, these tests fail — they are
//! the guard against mirror-image drift between the two
//! implementations.
//!
//! The iOS family is exempt: the reference's list order is random (Go
//! map iteration), so only shape is asserted there (in src/data/ios.zig).
//! The windows *version* picks are also exempt from strict parity:
//! this package prepends "Windows 11" to the version list (the
//! upstream Jan-2022 list stops at Windows 10), so the version divisor
//! is 5 here vs 4 upstream. The goldens below were recomputed with the
//! same independent script against our 5-entry list; model picks
//! (divisor 790, list untouched) remain strict parity.

const std = @import("std");
const devman = @import("device_manager");
const td = @import("td");

// The query constructor used in the wire tests below must match the
// committed generated API (same cross-check pattern as td's bot-login
// example; fails at compile time when td's schema layer changes).
const updates_get_state_id: u32 = 0xedd4882a;
comptime {
    if (@hasDecl(td.api.updates, "getState"))
        std.debug.assert(td.api.updates.getState.constructor_id == updates_get_state_id);
}

fn generate(device: devman.Device, unique_id: []const u8) devman.Profile {
    var prng = std.Random.DefaultPrng.init(0);
    return device.generate(unique_id, prng.random());
}

test "reference parity: android family" {
    const cases = .{
        .{ "test-session", "Huawei ELE-L14", "SDK 23" },
        .{ "same-id", "Samsung SM-G9960", "SDK 31" },
        .{ "device-manager-demo", "HTC HTC Gratia A6380", "SDK 29" },
        .{ "concurrent-test", "HTC HTC Desire X", "SDK 24" },
    };
    inline for (cases) |c| {
        const p = generate(.android, c[0]);
        try std.testing.expectEqualStrings(c[1], p.device_model);
        try std.testing.expectEqualStrings(c[2], p.system_version);
    }

    // Same underlying android pick, different preset metadata per family.
    const android = generate(.android, "test-session");
    const android_x = generate(.android_x, "test-session");
    const plus = generate(.plus, "test-session");
    try std.testing.expectEqualStrings(android.device_model, android_x.device_model);
    try std.testing.expectEqualStrings(android.device_model, plus.device_model);
    try std.testing.expectEqualStrings("org.thunderdog.challegram", android_x.package_id);
    try std.testing.expectEqualStrings("org.telegram.plus", plus.package_id);
}

test "reference parity: windows and linux share the cleaned model pick" {
    const cases = .{
        .{ "test-session", "UL30VT" },
        .{ "same-id", "Satellite C855D" },
        .{ "device-manager-demo", "Satellite A665" },
        .{ "concurrent-test", "H81H3-AM" },
    };
    inline for (cases) |c| {
        const win = generate(.windows, c[0]);
        const lin = generate(.linux, c[0]);
        try std.testing.expectEqualStrings(c[1], win.device_model);
        try std.testing.expectEqualStrings(c[1], lin.device_model);
    }
    // Windows versions use our 5-entry list (Windows 11 prepended) —
    // see the module doc; models remain strict reference parity.
    try std.testing.expectEqualStrings("Windows 8", generate(.windows, "test-session").system_version);
    try std.testing.expectEqualStrings("Windows 8", generate(.windows, "same-id").system_version);
    try std.testing.expectEqualStrings("Windows 8", generate(.windows, "device-manager-demo").system_version);
    try std.testing.expectEqualStrings("Windows 11", generate(.windows, "concurrent-test").system_version);
    try std.testing.expectEqualStrings(
        "Linux GNOME X11 glibc 2.34",
        generate(.linux, "test-session").system_version,
    );
    try std.testing.expectEqualStrings(
        "Linux Unity Wayland glibc 2.31",
        generate(.linux, "concurrent-test").system_version,
    );
}

test "reference parity: macos" {
    const cases = .{
        .{ "test-session", "MacBook Air,", "macOS 11.6.2" },
        .{ "same-id", "MacBook Pro,", "macOS 10.15.3" },
        .{ "device-manager-demo", "iMac Pro,", "macOS 12.1" },
    };
    inline for (cases) |c| {
        const p = generate(.macos, c[0]);
        try std.testing.expectEqualStrings(c[1], p.device_model);
        try std.testing.expectEqualStrings(c[2], p.system_version);
    }
}

test "reference parity: desktop picks its OS from the same hash" {
    const a = generate(.desktop, "test-session");
    try std.testing.expectEqualStrings("MacBook Air,", a.device_model); // h%3 -> macos
    const b = generate(.desktop, "same-id");
    try std.testing.expectEqualStrings("Satellite C855D", b.device_model); // h%3 -> windows
    try std.testing.expectEqualStrings("Windows 8", b.system_version); // 5-entry list, see module doc
    const c = generate(.desktop, "device-manager-demo");
    try std.testing.expectEqualStrings(
        "Linux MATE XWayland glibc 2.31",
        c.system_version,
    ); // h%3 -> linux

    // And an explicit system always wins over the hashed choice.
    var prng = std.Random.DefaultPrng.init(0);
    const forced = devman.generate_desktop(.linux, "test-session", prng.random());
    try std.testing.expectEqualStrings(
        "Linux GNOME X11 glibc 2.34",
        forced.system_version,
    );
}

test "generate preserves preset metadata while swapping device" {
    const p = generate(.android, "test-session");
    try std.testing.expectEqual(devman.Platform.android, p.platform);
    try std.testing.expectEqualStrings("8.4.1 (2522)", p.app_version);
    try std.testing.expectEqualStrings("android", p.lang_pack);

    const d = generate(.windows, "test-session");
    try std.testing.expectEqual(devman.Platform.desktop, d.platform);
    try std.testing.expectEqualStrings("tdesktop", d.lang_pack);
    try std.testing.expectEqualStrings("5.10.0 x64", d.app_version);
}

test "wire bridge wraps an arbitrary td query" {
    var w = td.tl.Writer.init(std.testing.allocator);
    defer w.deinit();
    try w.writeConstructorId(updates_get_state_id);

    const profile = devman.telegram_ios();
    var wrapped = td.tl.Writer.init(std.testing.allocator);
    defer wrapped.deinit();
    try devman.init_connection.write_invoke_with_layer_init_connection(
        &wrapped,
        devman.init_connection.api_layer,
        2040,
        profile,
        w.items(),
    );

    // Unwrap: header + six profile strings, then the untouched query.
    var r = td.tl.Reader.init(wrapped.items());
    try std.testing.expectEqual(devman.init_connection.invoke_with_layer_id, try r.readConstructorId());
    try std.testing.expectEqual(devman.init_connection.api_layer, try r.readInt());
    try std.testing.expectEqual(devman.init_connection.init_connection_id, try r.readConstructorId());
    try std.testing.expectEqual(@as(i32, 0), try r.readInt());
    try std.testing.expectEqual(@as(i32, 2040), try r.readInt());
    try std.testing.expectEqualStrings("iPhone 13 Pro Max", try r.readString());
    try std.testing.expectEqualStrings("14.8.1", try r.readString());
    try std.testing.expectEqualStrings("8.4", try r.readString());
    try std.testing.expectEqualStrings("en-US", try r.readString());
    try std.testing.expectEqualStrings("ios", try r.readString());
    try std.testing.expectEqualStrings("en", try r.readString());
    try std.testing.expectEqualSlices(u8, w.items(), r.data[r.pos..]);
}

test "generate_desktop_with_arch reports the host arch" {
    var prng = std.Random.DefaultPrng.init(0);
    const p = devman.generate_desktop_with_arch(null, "test-session", prng.random());
    const arch = @import("builtin").cpu.arch;
    const expected: []const u8 = switch (arch) {
        .x86_64 => "PC 64bit",
        .x86 => "PC 32bit",
        .aarch64 => "arm64",
        else => @tagName(arch),
    };
    try std.testing.expectEqualStrings(expected, p.device_model);
}
