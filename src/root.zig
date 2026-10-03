//! device-manager — realistic Telegram client device profiles for td.
//!
//! A `Profile` bundles the device identity fields (device model, system
//! version, app version, language codes, lang pack, …) Telegram sees
//! during `initConnection`. Profiles can be:
//!
//!   * picked from official presets — `telegram_desktop()`,
//!     `telegram_android()`, …;
//!   * generated deterministically from a unique id —
//!     `generate_android("session-1", random)`, …;
//!   * generated via the `Device` enum — `Device.android.generate("s", r)`.
//!
//! Deterministic generation means the same unique id always yields the
//! same device model and system version — stable session identities
//! across restarts. An empty unique id selects at random (the `random`
//! argument is only consulted on that path).
//!
//! The selection math (SHA-1-derived hash, list indexing) is a faithful
//! port of mtgo-labs/device-manager, so identical unique ids map to the
//! same devices as the reference — except the iOS family, whose list
//! order is random in the reference (Go map iteration) and fixed here.
//!
//! The wire side lives in `init_connection`: it wraps any serialized
//! query in `invokeWithLayer(initConnection(...))` using a profile.

const std = @import("std");

pub const text = @import("text.zig");
pub const data = @import("data/mod.zig");
pub const credentials = @import("credentials.zig");
pub const init_connection = @import("init_connection.zig");

pub const DeviceInfo = data.DeviceInfo;

/// Platform a client identifies as, for Telegram's feature gating
/// (reference `types.ClientPlatform`).
pub const Platform = enum {
    android,
    ios,
    desktop,
    web,

    pub fn str(self: Platform) []const u8 {
        return switch (self) {
            .android => "android",
            .ios => "ios",
            .desktop => "desktop",
            .web => "web",
        };
    }
};

/// Telegram client device types (reference `Device` enum).
pub const Device = enum {
    /// Official Telegram Android client.
    android,
    /// Telegram-X Android client.
    android_x,
    /// Plus Messenger Android client.
    plus,
    /// Official Telegram iOS client.
    ios,
    /// Official Telegram macOS client.
    macos,
    /// Telegram Desktop with a Windows system version.
    windows,
    /// Telegram Desktop with a Linux system version.
    linux,
    /// Telegram Desktop with a deterministically chosen OS.
    desktop,
    /// Telegram Web Z (React client).
    web_z,
    /// Telegram Web K client.
    web_k,
    /// Telegram Webogram client.
    webogram,

    /// Parses a reference device name ("android_x", "web_k", …);
    /// unknown names map to null (the reference falls back to a
    /// random desktop profile there).
    pub fn from_string(name: []const u8) ?Device {
        inline for (std.meta.fields(Device)) |f| {
            if (std.mem.eql(u8, name, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }

    /// The profile for this device type; `unique_id` drives the
    /// deterministic choice (empty → random via `random`). Web clients
    /// ignore both and return their static profile.
    pub fn generate(self: Device, unique_id: []const u8, random: std.Random) Profile {
        return switch (self) {
            .android => generate_android(unique_id, random),
            .android_x => generate_android_x(unique_id, random),
            .plus => generate_plus(unique_id, random),
            .ios => generate_ios(unique_id, random),
            .macos => generate_macos(unique_id, random),
            .windows => generate_desktop(.windows, unique_id, random),
            .linux => generate_desktop(.linux, unique_id, random),
            .desktop => generate_desktop(null, unique_id, random),
            .web_z => telegram_web_z(),
            .web_k => telegram_web_k(),
            .webogram => telegram_webogram(),
        };
    }

    pub fn str(self: Device) []const u8 {
        return switch (self) {
            .android => "android",
            .android_x => "android_x",
            .plus => "plus",
            .ios => "ios",
            .macos => "macos",
            .windows => "windows",
            .linux => "linux",
            .desktop => "desktop",
            .web_z => "web_z",
            .web_k => "web_k",
            .webogram => "webogram",
        };
    }
};

/// A Telegram client device identity: the fields reported to Telegram
/// during `initConnection`. Value type — copying is free, all strings
/// are static (presets) or slices into the comptime data tables.
pub const Profile = struct {
    /// Identifies the client application; applied together with
    /// `api_hash` when both are set (see `credentials`).
    api_id: i32 = 0,
    api_hash: []const u8 = "",
    /// Hardware model (e.g. "iPhone 13 Pro Max").
    device_model: []const u8,
    /// OS version (e.g. "SDK 31", "Windows 10").
    system_version: []const u8,
    /// Client app version (e.g. "8.4.1 (2522)").
    app_version: []const u8,
    /// Two-letter ISO 639-1 UI language code (e.g. "en").
    lang_code: []const u8,
    /// Device-level language code (e.g. "en-US").
    system_lang_code: []const u8,
    /// Translation pack name (e.g. "tdesktop", "android").
    lang_pack: []const u8,
    /// Platform Telegram gates features by.
    platform: Platform,
    /// Native application package / bundle identifier.
    package_id: []const u8 = "",

    /// Returns a copy with `device_model`/`system_version` overridden
    /// (reference `WithDevice`).
    pub fn with_device(self: Profile, device_model: []const u8, system_version: []const u8) Profile {
        var copy = self;
        copy.device_model = device_model;
        copy.system_version = system_version;
        return copy;
    }

    /// `with_device` from a `DeviceInfo` pair.
    pub fn with_device_from(self: Profile, info: DeviceInfo) Profile {
        return self.with_device(info.model, info.version);
    }

    /// Multi-line human-readable dump (`{f}` formatting).
    pub fn format(self: *const Profile, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print(
            \\Profile:
            \\    device_model:     {s}
            \\    system_version:   {s}
            \\    app_version:      {s}
            \\    lang_code:        {s}
            \\    system_lang_code: {s}
            \\    lang_pack:        {s}
            \\    platform:         {s}
            \\    package_id:       {s}
            \\    api_id:           {d}
            \\
        , .{
            self.device_model,     self.system_version,
            self.app_version,      self.lang_code,
            self.system_lang_code, self.lang_pack,
            self.platform.str(),   self.package_id,
            self.api_id,
        });
    }
};

// ------------------------------------------------------------ presets

/// Telegram Desktop on Windows (static).
pub fn telegram_desktop() Profile {
    return credentials.apply("telegram_desktop_official", .{
        .device_model = "Desktop",
        .system_version = "Windows 10",
        .app_version = "5.10.0 x64",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "tdesktop",
        .platform = .desktop,
        .package_id = "org.telegram.desktop",
    });
}

/// Official Telegram Android app (static).
pub fn telegram_android() Profile {
    return credentials.apply("telegram_android", .{
        .device_model = "Samsung SM-G998B",
        .system_version = "SDK 31",
        .app_version = "8.4.1 (2522)",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "android",
        .platform = .android,
        .package_id = "org.telegram.messenger",
    });
}

/// Telegram-X for Android (static).
pub fn telegram_android_x() Profile {
    return credentials.apply("telegram_x", .{
        .device_model = "Samsung SM-G998B",
        .system_version = "SDK 31",
        .app_version = "8.4.1 (2522)",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "android",
        .platform = .android,
        .package_id = "org.thunderdog.challegram",
    });
}

/// Plus Messenger for Android (static).
pub fn telegram_plus() Profile {
    return credentials.apply("plus_messenger", .{
        .device_model = "Samsung SM-G998B",
        .system_version = "SDK 31",
        .app_version = "8.4.1 (2522)",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "android",
        .platform = .android,
        .package_id = "org.telegram.plus",
    });
}

/// Official Telegram iOS app (static).
pub fn telegram_ios() Profile {
    return credentials.apply("telegram_ios", .{
        .device_model = "iPhone 13 Pro Max",
        .system_version = "14.8.1",
        .app_version = "8.4",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "ios",
        .platform = .ios,
        .package_id = "ph.telegra.Telegraph",
    });
}

/// Official Telegram macOS app (static).
pub fn telegram_macos() Profile {
    return credentials.apply("telegram_macos", .{
        .device_model = "MacBook Pro",
        .system_version = "macOS 12.0.1",
        .app_version = "8.4",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "macos",
        .platform = .desktop,
        .package_id = "ru.keepcoder.Telegram",
    });
}

/// Telegram Web Z, the React web client (static).
pub fn telegram_web_z() Profile {
    return .{
        .device_model = web_ua,
        .system_version = "Windows",
        .app_version = "1.28.3 Z",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "",
        .platform = .web,
    };
}

/// Telegram Web K client (static; upstream really sets lang_pack
/// "macos" here — ported as-is).
pub fn telegram_web_k() Profile {
    return credentials.apply("telegram_web_k", .{
        .device_model = web_ua,
        .system_version = "Win32",
        .app_version = "1.0.1 K",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "macos",
        .platform = .web,
    });
}

/// Telegram Webogram client (static).
pub fn telegram_webogram() Profile {
    return .{
        .device_model = web_ua,
        .system_version = "Win32",
        .app_version = "0.7.0",
        .lang_code = "en",
        .system_lang_code = "en-US",
        .lang_pack = "",
        .platform = .web,
    };
}

const web_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36";

// ------------------------------------------------------------- generate

/// OS family a generated desktop profile reports.
pub const DesktopSystem = enum { windows, macos, linux };

/// Randomized Telegram Desktop profile. `system` chooses the OS
/// (`null` → chosen deterministically from `unique_id`, like the
/// reference's empty-string argument).
pub fn generate_desktop(system: ?DesktopSystem, unique_id: []const u8, random: std.Random) Profile {
    const base = telegram_desktop();
    const h = hash_str(unique_id, random);

    const sys: DesktopSystem = system orelse
        @enumFromInt(h % 3); // "windows", "macos", "linux" in order

    const info: DeviceInfo = switch (sys) {
        .windows => random_windows_device(h),
        .macos => random_macos_device(h),
        .linux => random_linux_device(h),
    };
    return base.with_device(info.model, info.version);
}

/// Randomized Telegram Android profile.
pub fn generate_android(unique_id: []const u8, random: std.Random) Profile {
    return telegram_android().with_device_from(random_android_device(hash_str(unique_id, random)));
}

/// Randomized Telegram-X Android profile.
pub fn generate_android_x(unique_id: []const u8, random: std.Random) Profile {
    return telegram_android_x().with_device_from(random_android_device(hash_str(unique_id, random)));
}

/// Randomized Plus Messenger Android profile.
pub fn generate_plus(unique_id: []const u8, random: std.Random) Profile {
    return telegram_plus().with_device_from(random_android_device(hash_str(unique_id, random)));
}

/// Randomized Telegram iOS profile.
pub fn generate_ios(unique_id: []const u8, random: std.Random) Profile {
    return telegram_ios().with_device_from(random_ios_device(hash_str(unique_id, random)));
}

/// Randomized Telegram macOS profile.
pub fn generate_macos(unique_id: []const u8, random: std.Random) Profile {
    return telegram_macos().with_device_from(random_macos_device(hash_str(unique_id, random)));
}

/// Telegram Desktop profile whose `device_model` reports the actual
/// CPU architecture ("PC 64bit" / "PC 32bit" / the arch name), the way
/// Telegram Desktop itself does (reference `GenerateDesktopWithArch`).
pub fn generate_desktop_with_arch(system: ?DesktopSystem, unique_id: []const u8, random: std.Random) Profile {
    const p = generate_desktop(system, unique_id, random);
    return p.with_device(current_arch_model, p.system_version);
}

const current_arch_model: []const u8 = switch (@import("builtin").cpu.arch) {
    .x86_64 => "PC 64bit",
    .x86 => "PC 32bit",
    .aarch64 => "arm64",
    else => @tagName(@import("builtin").cpu.arch),
};

// -------------------------------------------------- platform pickers
//
// Each mirrors the reference: model = list[h % len], version =
// list[(h / len) % len] — the same single hash drives both, with the
// division decorrelating the pair.

fn random_android_device(h: u64) DeviceInfo {
    const models = data.android.device_models;
    const versions = data.android.system_versions;
    return .{
        .model = models[h % models.len],
        .version = versions[(h / models.len) % versions.len],
    };
}

fn random_ios_device(h: u64) DeviceInfo {
    const list = data.ios.device_list;
    return .{
        .model = list[h % list.len].model,
        .version = list[h % list.len].version,
    };
}

fn random_macos_device(h: u64) DeviceInfo {
    const models = data.macos.device_models;
    const versions = data.macos.system_versions;
    return .{
        .model = models[h % models.len],
        .version = versions[(h / models.len) % versions.len],
    };
}

fn random_windows_device(h: u64) DeviceInfo {
    const models = data.desktop_clean.cleaned_models;
    const versions = data.desktop.windows_system_versions;
    return .{
        .model = models[h % models.len],
        .version = versions[(h / models.len) % versions.len],
    };
}

fn random_linux_device(h: u64) DeviceInfo {
    const models = data.desktop_clean.cleaned_models;
    const versions = data.linux.system_versions;
    return .{
        .model = models[h % models.len],
        .version = versions[(h / models.len) % versions.len],
    };
}

// -------------------------------------------------------------- hash

/// Deterministic u64 hash of `unique_id`: SHA-1, first 8 bytes
/// big-endian, reduced mod 10^12. An empty `unique_id` hashes 32 bytes
/// drawn from `random` instead (the reference uses crypto/rand there).
pub fn hash_str(unique_id: []const u8, random: std.Random) u64 {
    var random_bytes: [32]u8 = undefined;
    const input: []const u8 = if (unique_id.len == 0) blk: {
        random.bytes(&random_bytes);
        break :blk random_bytes[0..];
    } else unique_id;

    var digest: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(input, &digest, .{});
    return std.mem.readInt(u64, digest[0..8], .big) % 1_000_000_000_000;
}

// -------------------------------------------------------------- tests

test "hash_str matches the reference derivation" {
    // Independently computed: SHA-1(id)[0..8] big-endian mod 10^12,
    // via Python hashlib.
    var prng = std.Random.DefaultPrng.init(0);
    const expect_eq = std.testing.expectEqual;
    try expect_eq(@as(u64, 715_703_492_425), hash_str("test-session", prng.random()));
    try expect_eq(@as(u64, 349_668_723_888), hash_str("same-id", prng.random()));
    try expect_eq(@as(u64, 912_191_765_135), hash_str("concurrent-test", prng.random()));
}

test "deterministic generation: same id, same device" {
    var prng = std.Random.DefaultPrng.init(1);
    const a = Device.windows.generate("same-id", prng.random());
    const b = Device.windows.generate("same-id", prng.random());
    try std.testing.expectEqualStrings(a.device_model, b.device_model);
    try std.testing.expectEqualStrings(a.system_version, b.system_version);

    const c = Device.android.generate("same-id", prng.random());
    const d = Device.android.generate("same-id", prng.random());
    try std.testing.expectEqualStrings(c.device_model, d.device_model);
    try std.testing.expectEqualStrings(c.system_version, d.system_version);
}

test "every device type generates a non-empty profile" {
    var prng = std.Random.DefaultPrng.init(2);
    inline for (std.meta.fields(Device)) |f| {
        const device: Device = @enumFromInt(f.value);
        const p = device.generate("test-session", prng.random());
        try std.testing.expect(p.device_model.len > 0);
        try std.testing.expect(p.system_version.len > 0);
        try std.testing.expect(p.app_version.len > 0);
    }
}

test "empty unique id takes the random path" {
    var prng_a = std.Random.DefaultPrng.init(3);
    var prng_b = std.Random.DefaultPrng.init(4);
    const a = Device.android.generate("", prng_a.random());
    const b = Device.android.generate("", prng_b.random());
    // Astronomically unlikely to collide on both fields with two seeds.
    const identical = std.mem.eql(u8, a.device_model, b.device_model) and
        std.mem.eql(u8, a.system_version, b.system_version);
    try std.testing.expect(!identical);
}

test "with_device overrides without mutating the original" {
    const base = telegram_desktop();
    const modified = base.with_device("TestModel", "TestOS");
    try std.testing.expectEqualStrings("TestModel", modified.device_model);
    try std.testing.expectEqualStrings("TestOS", modified.system_version);
    try std.testing.expect(!std.mem.eql(u8, base.device_model, modified.device_model));
}

test "device from_string round trip" {
    inline for (std.meta.fields(Device)) |f| {
        const device = Device.from_string(f.name) orelse return error.UnknownDeviceName;
        try std.testing.expectEqualStrings(f.name, device.str());
    }
    try std.testing.expect(Device.from_string("nokia_3310") == null);
}

test "presets match the reference fields" {
    const desktop_p = telegram_desktop();
    try std.testing.expectEqualStrings("tdesktop", desktop_p.lang_pack);
    try std.testing.expectEqualStrings("org.telegram.desktop", desktop_p.package_id);
    try std.testing.expect(Platform.desktop == desktop_p.platform);

    const android_p = telegram_android();
    try std.testing.expectEqualStrings("android", android_p.lang_pack);
    try std.testing.expectEqualStrings("org.telegram.messenger", android_p.package_id);
    try std.testing.expect(Platform.android == android_p.platform);

    try std.testing.expectEqualStrings("org.thunderdog.challegram", telegram_android_x().package_id);
    try std.testing.expectEqualStrings("org.telegram.plus", telegram_plus().package_id);
    try std.testing.expectEqualStrings("ph.telegra.Telegraph", telegram_ios().package_id);
    try std.testing.expect(Platform.ios == telegram_ios().platform);

    const macos_p = telegram_macos();
    try std.testing.expectEqualStrings("macos", macos_p.lang_pack);
    try std.testing.expectEqualStrings("ru.keepcoder.Telegram", macos_p.package_id);

    try std.testing.expect(Platform.web == telegram_web_z().platform);
    try std.testing.expectEqualStrings("1.28.3 Z", telegram_web_z().app_version);
    try std.testing.expectEqualStrings("macos", telegram_web_k().lang_pack);
    try std.testing.expectEqualStrings("0.7.0", telegram_webogram().app_version);
    try std.testing.expect(telegram_web_z().package_id.len == 0);
    try std.testing.expect(telegram_webogram().package_id.len == 0);
}

test "generate over many ids stays non-empty and stable" {
    var prng = std.Random.DefaultPrng.init(5);
    for (0..100) |i| {
        var buf: [16]u8 = undefined;
        const id = std.fmt.bufPrint(&buf, "session-{d}", .{i}) catch unreachable;
        const p = generate_android(id, prng.random());
        try std.testing.expect(p.device_model.len > 0);
        try std.testing.expect(p.system_version.len > 0);
    }
}

test {
    _ = @import("text.zig");
    _ = @import("data/mod.zig");
    _ = @import("credentials.zig");
    _ = @import("init_connection.zig");
}
