//! The wire side of a device profile: wrapping a query in
//! `invokeWithLayer(layer, initConnection(...))` — the
//! connection-establishment wrap every fresh MTProto session needs
//! once (a bare first query answers `400 CONNECTION_NOT_INITED`).
//!
//! This is the device-manager equivalent of the reference `Profile.Apply`:
//! instead of injecting into a config struct, the profile is injected
//! into the serialized request itself, using `td`'s TL writer — the
//! same encoding `td`'s bot-login example hand-writes and has verified
//! against a production DC.
//!
//!   invokeWithLayer#da9b0d0d {layer:int} query:!X = X
//!   initConnection#c1cd5ea9 flags:# api_id:int device_model:string
//!     system_version:string app_version:string system_lang_code:string
//!     lang_pack:string lang_code:string
//!     proxy:flags.0?InputClientProxy params:flags.1?JSONValue
//!     query:!X = X

const std = @import("std");
const td = @import("td");
const root = @import("root.zig");

pub const invoke_with_layer_id: u32 = 0xda9b0d0d;
pub const init_connection_id: u32 = 0xc1cd5ea9;

/// Must match `// LAYER N` of td's `tests/data/telegram_api.tl` — the
/// schema its generated `td.api` tree was built from (the layer is the
/// only version handshake MTProto has). The generic wrappers above are
/// not part of the generated tree, so this constant lives here.
pub const api_layer: i32 = 229;

/// Writes `invokeWithLayer(layer, initConnection(..., query))` into
/// `w`. `query` is an already-serialized request body (constructor id
/// + parameters), appended verbatim. `api_id` is used unless the
/// profile carries registered credentials (`profile.api_id != 0` and
/// `profile.api_hash` set), mirroring the reference's conditional
/// credential application.
pub fn write_invoke_with_layer_init_connection(
    w: *td.tl.Writer,
    layer: i32,
    api_id: i32,
    profile: root.Profile,
    query: []const u8,
) td.TlError!void {
    const effective_api_id = if (profile.api_id != 0 and profile.api_hash.len > 0)
        profile.api_id
    else
        api_id;

    try w.writeConstructorId(invoke_with_layer_id);
    try w.writeInt(layer);
    try w.writeConstructorId(init_connection_id);
    try w.writeInt(0); // flags: no proxy, no params
    try w.writeInt(effective_api_id);
    try w.writeString(profile.device_model);
    try w.writeString(profile.system_version);
    try w.writeString(profile.app_version);
    try w.writeString(profile.system_lang_code);
    try w.writeString(profile.lang_pack);
    try w.writeString(profile.lang_code);
    try w.writeRaw(query);
}

/// Allocating form of `write_invoke_with_layer_init_connection`; the
/// caller owns the returned bytes.
pub fn serialize_invoke_with_layer_init_connection(
    gpa: std.mem.Allocator,
    layer: i32,
    api_id: i32,
    profile: root.Profile,
    query: []const u8,
) td.TlError![]u8 {
    var w = td.tl.Writer.init(gpa);
    errdefer w.deinit();
    try write_invoke_with_layer_init_connection(&w, layer, api_id, profile, query);
    return w.toOwnedSlice();
}

test "golden bytes: exact wire layout" {
    // Expected layout hand-assembled from the schema (constructor ids
    // little-endian, TL strings length-prefixed and padded to 4-byte
    // boundaries), independent of the writer under test — the wire
    // format a production DC has accepted for this wrap.
    const expected = [_]u8{
        0x0d, 0x0d, 0x9b, 0xda, // invokeWithLayer#da9b0d0d
        0xe5, 0x00, 0x00, 0x00, // layer 229
        0xa9, 0x5e, 0xcd, 0xc1, // initConnection#c1cd5ea9
        0x00, 0x00, 0x00, 0x00, // flags 0
        0xf8, 0x07, 0x00, 0x00, // api_id 2040
        0x02, 'S', 'M', 0x00, // "SM"
        0x06, 'S', 'D', 'K', ' ', '3', '1', 0x00, // "SDK 31"
        0x03, '1', '.', '0', // "1.0"
        0x02, 'e', 'n', 0x00, // "en" (system_lang_code)
        0x00, 0x00, 0x00, 0x00, // "" (lang_pack)
        0x02, 'e', 'n', 0x00, // "en" (lang_code)
        0x2a, 0x88, 0xd4, 0xed, // query: updates.getState#edd4882a
    };

    const profile = root.Profile{
        .device_model = "SM",
        .system_version = "SDK 31",
        .app_version = "1.0",
        .lang_code = "en",
        .system_lang_code = "en",
        .lang_pack = "",
        .platform = .android,
    };

    const bytes = try serialize_invoke_with_layer_init_connection(
        std.testing.allocator,
        api_layer,
        2040,
        profile,
        &.{ 0x2a, 0x88, 0xd4, 0xed },
    );
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, &expected, bytes);
}

test "round trip through td's reader" {
    const profile = root.telegram_android();
    const query = [_]u8{ 0x2a, 0x88, 0xd4, 0xed };

    const bytes = try serialize_invoke_with_layer_init_connection(
        std.testing.allocator,
        api_layer,
        2040,
        profile,
        &query,
    );
    defer std.testing.allocator.free(bytes);

    var r = td.tl.Reader.init(bytes);
    try std.testing.expectEqual(invoke_with_layer_id, try r.readConstructorId());
    try std.testing.expectEqual(api_layer, try r.readInt());
    try std.testing.expectEqual(init_connection_id, try r.readConstructorId());
    try std.testing.expectEqual(@as(i32, 0), try r.readInt()); // flags
    try std.testing.expectEqual(@as(i32, 2040), try r.readInt()); // api_id
    try std.testing.expectEqualStrings(profile.device_model, try r.readString());
    try std.testing.expectEqualStrings(profile.system_version, try r.readString());
    try std.testing.expectEqualStrings(profile.app_version, try r.readString());
    try std.testing.expectEqualStrings(profile.system_lang_code, try r.readString());
    try std.testing.expectEqualStrings(profile.lang_pack, try r.readString());
    try std.testing.expectEqualStrings(profile.lang_code, try r.readString());
    try std.testing.expectEqualSlices(u8, &query, r.data[r.pos..]);
}

test "registered profile credentials win over the api_id argument" {
    defer root.credentials.reset();
    try root.credentials.register("telegram_android", .{ .api_id = 42, .api_hash = "hash" });
    const profile = root.telegram_android();

    const bytes = try serialize_invoke_with_layer_init_connection(
        std.testing.allocator,
        api_layer,
        2040,
        profile,
        &.{ 0x2a, 0x88, 0xd4, 0xed },
    );
    defer std.testing.allocator.free(bytes);

    var r = td.tl.Reader.init(bytes);
    _ = try r.readConstructorId(); // invokeWithLayer
    _ = try r.readInt(); // layer
    _ = try r.readConstructorId(); // initConnection
    _ = try r.readInt(); // flags
    try std.testing.expectEqual(@as(i32, 42), try r.readInt()); // api_id from profile
}
