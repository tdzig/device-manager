const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const td = b.dependency("td", .{
        .target = target,
        .optimize = optimize,
    }).module("td");

    // The library module: pure data + deterministic generation, with
    // the td wire bridge in `init_connection`.
    const device_manager = b.addModule("device_manager", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "td", .module = td },
        },
    });

    // Example: runnable, network-free demonstration of the public API,
    // built by the default step so it can never rot.
    const example_exe = b.addExecutable(.{
        .name = "device-manager-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/list_devices.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "device_manager", .module = device_manager },
            },
        }),
    });
    b.installArtifact(example_exe);

    // Unit tests: the module itself is the test root, so every inline
    // `test` declaration in its files is collected (device data,
    // presets, deterministic generation, credentials, wire layout).
    const unit_tests = b.addTest(.{ .root_module = device_manager });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Integration tests: golden wire bytes, td-reader round trip and
    // reference-parity selections against the td module.
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/device.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "device_manager", .module = device_manager },
                .{ .name = "td", .module = td },
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
}
