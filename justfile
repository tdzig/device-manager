# device-manager — task runner
#
# Zig is provided through nix (it is not on PATH in this environment);
# override with `just --set ZIG zig` when a system zig is available.

zig := "nix run nixpkgs#zig --"
default:
    @just --list

# Build the library module, the example binary, and tests
build:
    {{zig}} build

# Run all tests (unit inline tests + reference-parity integration tests)
test:
    {{zig}} build test --summary all

# Build and run the device listing example (deterministic, network-free)
example: build
    ./zig-out/bin/device-manager-example

# Remove build artifacts
clean:
    rm -rf .zig-cache zig-out
