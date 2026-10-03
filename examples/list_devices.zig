//! Example: print a generated profile for every device type — the
//! deterministic mapping for one fixed unique id, plus one random
//! draw — and show the `invokeWithLayer(initConnection(...))` bytes a
//! profile produces around a real query.
//!
//! Deterministic by design: the same unique id ("device-manager-demo"
//! here) prints the same devices on every run and on every machine.
//!
//! Run: `./zig-out/bin/device-manager-example` (after `just build`).

const std = @import("std");
const devman = @import("device_manager");

const demo_unique_id = "device-manager-demo";

fn printProfile(tag: []const u8, p: devman.Profile) void {
    std.debug.print(
        \\== {s}
        \\    device_model:     {s}
        \\    system_version:   {s}
        \\    app_version:      {s}
        \\    lang_code:        {s}
        \\    system_lang_code: {s}
        \\    lang_pack:        {s}
        \\    platform:         {s}
        \\    package_id:       {s}
        \\
    , .{
        tag,              p.device_model,
        p.system_version, p.app_version,
        p.lang_code,      p.system_lang_code,
        p.lang_pack,      p.platform.str(),
        p.package_id,
    });
}

pub fn main(init: std.process.Init) !void {
    var rng_source = std.Random.IoSource{ .io = init.io };
    const random = rng_source.interface();

    std.debug.print("device-manager — every device type for unique id \"{s}\"\n\n", .{demo_unique_id});
    inline for (std.meta.fields(devman.Device)) |f| {
        const device: devman.Device = @enumFromInt(f.value);
        printProfile(device.str(), device.generate(demo_unique_id, random));
    }

    // One random draw (empty unique id): different on every run.
    printProfile("random draw (empty unique id)", devman.Device.android.generate("", random));

    // The wire side: a profile wrapped around updates.getState.
    const profile = devman.telegram_desktop();
    const query = [_]u8{ 0xed, 0xd4, 0x88, 0x2a }; // updates.getState#edd4882a
    const bytes = try devman.init_connection.serialize_invoke_with_layer_init_connection(
        init.gpa,
        devman.init_connection.api_layer,
        2040,
        profile,
        &query,
    );
    defer init.gpa.free(bytes);

    std.debug.print(
        "== telegram_desktop + updates.getState = invokeWithLayer(initConnection(...))\n  first bytes: {s}\n  total: {d} bytes (layer {d}; api_id 2040, or from registered profile credentials)\n",
        .{ std.fmt.bytesToHex(bytes[0..24], .lower), bytes.len, devman.init_connection.api_layer },
    );
}
