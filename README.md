# device-manager

Realistic Telegram client **device profiles** for the [`td`](../td)
MTProto library — a Zig port of
[mtgo-labs/device-manager](https://github.com/mtgo-labs/device-manager).

A `Profile` bundles the device identity fields Telegram sees during
`initConnection` (device model, system version, app version, language
codes, lang pack, platform, package id). Profiles can be:

- picked from official presets — `telegram_desktop()`, `telegram_android()`, …;
- generated deterministically from a unique id — `generate_android("session-1", random)`, …;
- generated via the `Device` enum — `Device.android.generate("session-1", random)`.

Deterministic generation means the same unique id always yields the same
device model and system version — stable session identities across
restarts. An empty unique id draws at random (the `random` argument is
only consulted on that path).

## Quick start

```zig
const devman = @import("device_manager");
const td = @import("td");

// 1. Deterministic device for a session id.
var prng = std.Random.DefaultPrng.init(0);
const profile = devman.Device.android.generate("my-session", prng.random());

// 2. Wrap any serialized query in invokeWithLayer(initConnection(...))
//    — the wrap every fresh MTProto session needs once.
const query = try serializeMyRequest(gpa);
const req = try devman.init_connection.serialize_invoke_with_layer_init_connection(
    gpa, devman.init_connection.api_layer, api_id, profile, query,
);
const answer = try rpc_client.invokeRaw(io, req);
```

Presets and generation:

```zig
devman.telegram_desktop()      // static Telegram Desktop (Windows)
devman.telegram_android()      // static official Android app
devman.telegram_ios()          // … android_x, plus, macos, web_z, web_k, webogram
devman.generate_desktop(.linux, "bot-1", random); // null system → chosen from the hash
devman.Device.from_string("android_x");           // parse a reference device name
```

## Device types

| Type        | Description                                     |
| ----------- | ----------------------------------------------- |
| `android`   | official Telegram Android client                |
| `android_x` | Telegram-X Android client                       |
| `plus`      | Plus Messenger Android client                   |
| `ios`       | official Telegram iOS client                    |
| `macos`     | official Telegram macOS client                  |
| `windows`   | Telegram Desktop with a Windows system version  |
| `linux`     | Telegram Desktop with a Linux system version    |
| `desktop`   | Telegram Desktop with a randomly chosen OS      |
| `web_z`     | Telegram Web Z (React client)                   |
| `web_k`     | Telegram Web K client                           |
| `webogram`  | Telegram Webogram client                        |

## Reference parity

The selection math is a faithful port of the reference: SHA-1 of the
unique id, first 8 bytes big-endian, reduced mod 10¹²; model =
`list[h % len]`, version = `list[(h / len) % len]`. The device lists
were converted verbatim from the upstream Go literals (order and
duplicates preserved — selection indexes by position), so identical
unique ids map to the same devices as the reference library. The
integration tests (`tests/device.zig`) pin this with goldens computed
independently from the upstream source.

Three deliberate differences:

- **Windows 11** — prepended to the Windows version list (the reference
  list, from Jan-2022 data, stops at Windows 10; Telegram Desktop on
  Windows 11 reports "Windows 11"). Windows-family version picks
  therefore differ from the reference; model picks do not.
- **iOS list order** — the reference builds its iOS model×version list
  by iterating a Go map (random order), so its own iOS picks vary run
  to run. This port walks the table in source order and is fully
  deterministic.
- **No lazy initialization** — the reference materializes lists under
  `sync.Once`; here everything is a `const` (raw ports or comptime
  expansion), so there is no runtime state at all.

Quirks ported as-is (they are what the reference actually sends):
`clean_and_simplify` keeps a trailing space (upstream code vs. its doc
comment), macOS names keep the board-number comma ("MacBook Pro,"), and
the Web K preset reports lang_pack "macos".

## Credentials

Presets ship without api credentials (as upstream does). An embedding
application can attach them by name:

```zig
try devman.credentials.register("telegram_android", .{
    .api_id = 123456,
    .api_hash = "0123456789abcdef0123456789abcdef",
});
const profile = devman.telegram_android(); // now carries api_id/api_hash
```

Registered credentials also win over the explicit `api_id` argument in
`init_connection.serialize_invoke_with_layer_init_connection`.

## Layout

- `src/root.zig` — `Profile`, `Device`, `Platform`, presets, generation, `hash_str`
- `src/data/` — device tables (android/desktop converted verbatim; ios/macos/linux materialized at comptime)
- `src/credentials.zig` — optional per-preset api credential registry (thread-safe, allocation-free)
- `src/init_connection.zig` — the td wire bridge (`invokeWithLayer(initConnection(...))`)
- `tests/device.zig` — reference-parity goldens + wire tests
- `examples/list_devices.zig` — print every device type (`just example`)

## Attribution

Device lists and selection algorithm ported from
[mtgo-labs/device-manager](https://github.com/mtgo-labs/device-manager)
(Apache-2.0, commit `e3a65ab`); see `LICENSE` and `DATA-LICENSE`.
