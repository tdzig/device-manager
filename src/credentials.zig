//! Client credential registry: lets an embedding application attach
//! api_id/api_hash pairs to presets by name, without editing the
//! library — the mechanism the reference exposes through
//! `registerClientCredentials` / `withClientCredentials`.
//!
//! The registry ships **empty** (as upstream does): every preset keeps
//! `api_id == 0` / `api_hash == ""` until the embedder registers
//! credentials for its name. Registration is thread-safe (a small
//! spin lock — Zig 0.16's std carries no Mutex; registration is rare
//! and lookups are short scans, so spinning is fine); a fixed capacity
//! keeps it allocation- and deinit-free.

const std = @import("std");
const root = @import("root.zig");

pub const Credentials = struct {
    api_id: i32,
    api_hash: []const u8,
    /// Overrides the profile's package id when non-empty.
    package_id: []const u8 = "",
};

pub const Error = error{RegistryFull};

const Entry = struct {
    name: []const u8,
    creds: Credentials,
};

const capacity = 64;

var entries: [capacity]?Entry = .{null} ** capacity;
var lock_state = std.atomic.Value(u32).init(0); // 0 = free, 1 = held

fn lock() void {
    while (true) {
        if (lock_state.cmpxchgWeak(0, 1, .acquire, .monotonic) == null) return;
        std.Thread.yield() catch {};
    }
}

fn unlock() void {
    lock_state.store(0, .release);
}

/// Registers (or replaces, by name) the credentials a preset picks up.
/// The strings are borrowed, not copied — they must outlive every
/// `apply` call (string literals always do; a stack buffer declared
/// *inside* a loop does not — the loop reuses its memory and would
/// rewrite earlier entries' names through the borrowed slice).
pub fn register(name: []const u8, creds: Credentials) Error!void {
    lock();
    defer unlock();

    for (&entries) |*slot| {
        if (slot.*) |e| {
            if (std.mem.eql(u8, e.name, name)) {
                slot.* = .{ .name = name, .creds = creds };
                return;
            }
            continue;
        }
        slot.* = .{ .name = name, .creds = creds };
        return;
    }
    return error.RegistryFull;
}

/// Look up registered credentials by preset name.
pub fn lookup(name: []const u8) ?Credentials {
    lock();
    defer unlock();
    return lookup_locked(name);
}

/// Returns `profile` with registered credentials applied: api_id and
/// api_hash are set, and package_id is overridden when the entry
/// carries one (reference `withClientCredentials`). Without a
/// registered entry the profile passes through unchanged.
pub fn apply(name: []const u8, profile: root.Profile) root.Profile {
    var p = profile;
    lock();
    defer unlock();
    if (lookup_locked(name)) |creds| {
        p.api_id = creds.api_id;
        p.api_hash = creds.api_hash;
        if (creds.package_id.len > 0) p.package_id = creds.package_id;
    }
    return p;
}

/// Drops every registered entry (test helper).
pub fn reset() void {
    lock();
    defer unlock();
    for (&entries) |*slot| slot.* = null;
}

/// Caller must hold the lock.
fn lookup_locked(name: []const u8) ?Credentials {
    for (&entries) |slot| {
        if (slot) |e| {
            if (std.mem.eql(u8, e.name, name)) return e.creds;
        }
    }
    return null;
}

test "apply without registration is a pass-through" {
    const p = apply("telegram_android", .{
        .device_model = "m",
        .system_version = "v",
        .app_version = "a",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "android",
        .platform = .android,
    });
    try std.testing.expectEqual(@as(i32, 0), p.api_id);
    try std.testing.expectEqualStrings("", p.api_hash);
}

test "register, apply, replace" {
    defer reset();
    try register("test-client", .{ .api_id = 12345, .api_hash = "api-hash", .package_id = "example.package" });

    const p = apply("test-client", .{
        .device_model = "m",
        .system_version = "v",
        .app_version = "a",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "android",
        .platform = .android,
        .package_id = "original",
    });
    try std.testing.expectEqual(@as(i32, 12345), p.api_id);
    try std.testing.expectEqualStrings("api-hash", p.api_hash);
    try std.testing.expectEqualStrings("example.package", p.package_id);

    // Re-registering replaces.
    try register("test-client", .{ .api_id = 999, .api_hash = "other" });
    try std.testing.expectEqual(@as(i32, 999), lookup("test-client").?.api_id);
    try std.testing.expectEqualStrings("original", apply("test-client", .{
        .device_model = "m",
        .system_version = "v",
        .app_version = "a",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "android",
        .platform = .android,
        .package_id = "original",
    }).package_id);
}

test "registry capacity is enforced" {
    defer reset();
    // Buffers declared outside the loop: `register` borrows the name
    // slices, and a per-iteration buffer would be reused (rewriting
    // earlier entries' names through the borrowed slices).
    var name_bufs: [capacity][32]u8 = undefined;
    for (0..capacity, &name_bufs) |i, *buf| {
        const name = std.fmt.bufPrint(buf, "filler-{d}", .{i}) catch unreachable;
        try register(name, .{ .api_id = 1, .api_hash = "x" });
    }
    try std.testing.expectError(error.RegistryFull, register("overflow", .{ .api_id = 1, .api_hash = "x" }));
}
