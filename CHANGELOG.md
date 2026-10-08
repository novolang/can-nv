# Changelog

All notable changes to can-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

## 0.1.0 (2026-10-08)

The first release with bodies.  0.0.3, the interface release, had a
`todo()` for every body and no controller driver, no device half over a
board's controller, no loopback controller, no receive ring, no bit
timing solver and no CAN FD peripheral trait; this release adds each of
them, below.  It needs novo 0.19.3 or later, for embedded-hal-nv
0.3.0's `hal.can`.

The suites cover every line of `src/` on a host but for the regions
marked `cov: skip` with their reasons: the bxCAN and FDCAN drivers'
register access, and the `cansocket` paths that need a CAN interface,
which `tests/socketcan.sh` runs on vcan0 and vcan1 in a user network
namespace.

### Added

- `canboard`: `CanBoard`, the board's CAN controller behind
  `CanPeripheral[hw]`, over embedded-hal-nv 0.3.0's `CanBus` and
  `BoardCan`, for a board that serves `hal.can`: `board_open`,
  `board_started`, `board_bitrate`, and `to_bus_frame` and
  `of_bus_frame` between the two frame types.  One mailbox; an abort and
  a hardware filter are refused, and the controller recovers from
  bus-off by itself.  The package depends on embedded-hal-nv `^0.3.0`.
  The logic is in functions over any `CanBus`, `open_on`,
  `bus_transmit`, `bus_tx_done`, `bus_receive`, `bus_state` and
  `bus_recover`, which `CanBoard`'s methods call, so a program or a test
  drives it with a controller of its own.
- `canbxcan`: a driver for ST's bxCAN behind `CanPeripheral[hw]`: three
  mailboxes with displacement, 14 filter banks per instance in mask or
  list mode, normal, loopback, silent and silent-loopback modes, and
  bus-off recovery that aborts what is pending.  `btr_of` gives the
  CAN_BTR word and `id_bits` a filter bank's identifier word.
- `canfdcan`: a driver for ST's FDCAN (Bosch M_CAN) behind
  `CanPeripheral[hw]` and `CanFdPeripheral[hw]`: the message RAM laid out
  per instance, an eight-frame transmit queue in priority order, a
  16-frame receive FIFO of 64-byte elements, 28 standard and 8 extended
  filter elements, the internal and external loopback and monitor modes,
  bit rate switching, and bus-off recovery.  `nbtp_of` and `dbtp_of`
  give the timing words.
- `canloop`: a controller in memory for tests and emulators, with
  mailboxes, a receive FIFO, filters and the error counters, in a
  self-acknowledging mode and an alone-on-the-bus mode.
- `canring`: a receive ring over the caller's `Vec[CanFrame; N]`.
- `canhal.CanFdPeripheral[e]`: the CAN FD half of a controller.
- `canbus.solve_timing`, `CanBitTiming`, `CanTimingLimits`,
  `classic_limits`, `bxcan_limits`, `fdcan_nominal_limits`,
  `fdcan_data_limits`, `data_sample_point_permille` and the `timing_*`
  readers; `CAN_ERROR_WARNING_LIMIT` and `CAN_ERR_ALL`.
- `canfilter.list`, `list_ext`, `filter_is_list` and
  `CAN_FILTER_LIST`: a filter of two exact identifiers.
- `canframe.fd_none`, `fd_fault`, `fd_is_none`, `fd_is_fault`,
  `fd_is_frame`, `fd_is_fd` and `fd_of_classic`.
- `cantxq.refill_from`, for taking a frame out of the middle of the
  queue.
- `canerr` variants `CanTimingUnreachable`, `CanBusOff`,
  `CanFrameRefused`, `CanFilterNotSupported` and `CanShortWire`.

### Changed

- Every function of the interface has its body.  `cansocket` runs over
  `std.net`'s SocketCAN calls.
- The layer is `host`: the drivers perform `[hw]`.  `host_modules` is
  gone with it.
- The slot readers `cantxq` takes, and the payload readers
  `candump.render_fd_compact`, `cansocket.fd_frame_to_wire` and
  `send_fd` take, are `fn(Int) -> Int [mutate]`, and the functions that
  call them are charged `[mutate]`: a reader of the caller's storage
  reads a module-level `var`.
- `cansocket.receive_into` takes a `Vec[u8; 72]` rather than a
  `Cursor`, which no device build declares.
- The functions that build a refusal with a payload, and the `candump`
  and `canerr` text, are `@tier(rt)`; the SocketCAN calls are
  `@tier(app)`.
- `canframe.arbitration_key` orders frames as the bus does, with an
  extended identifier's top eleven bits compared first.  Two interface
  tests assumed `frame_ext(0x123, …)` shares 0x123's first eleven bits;
  they now use `0x123 << 18`.
- The interface's timing test named 7 MHz as a clock that cannot make
  500 kbit/s; 7 MHz makes it in 14 quanta.  The test uses 7.3728 MHz.
- The device probe counts the 44 checks it makes.

### Removed

- The dependency on heapless-nv.

## 0.0.3 — 2026-10-06

The interface is unchanged: no signature, type or effect row moved, and
every body is still `todo()`.

### Removed

- The dependency on heapless-nv, which is withdrawn.  No module used a
  heapless-nv type, so no signature changes.  The transmit queue's
  frames live in storage the caller declares, which on a device is one
  of the language's fixed-capacity collections, `Vec[CanFrame; N]`
  (SPEC section 14.8).  The comments in `cantxq`, `canisotp` and the
  device probe say so instead of naming heapless-nv.

### Changed

- The README's "Running on a microcontroller" section says what the
  registry shows: the embedded, rt and wasm tiers list the eight device
  modules, and `cansocket` is absent from them.  Version 0.0.2 was
  published on 2026-09-15, before the registry measured tiers per
  module (2026-09-23), so its page listed only the system and app
  tiers.  This release is the first whose page shows the split.
- The example carries the interface stamp beside it.
- Sentences about this project's state moved here from the README.  On
  2026-10-06 none of the boards novo-lang supports has a CAN controller
  on the die, and no DBC parser is published.  The probe command in the
  README was run against this release on that date.

## 0.0.2 — 2026-09-15

README rewritten to the package README style guide (docs/writing-a-readme.md); no change to the interface.

## 0.0.1 — 2026-09-12

The **interface**: every signature and every effect row, and no bodies.
`stability = "draft"`, and the release is recorded `implemented = false`.

### Added

- `canframe` — `CanFrame` and `CanFdFrame`, both identifier widths,
  remote and error frames, the payload packing, the data length codes
  for both formats, the arbitration key, the signal arithmetic, and the
  two not-a-frame values.
- `canfilter` — `CanFilter`, the acceptance arithmetic, the inverted
  sense, and `merge` / `covers` / `false_accept_width` for fitting more
  filters than a controller has slots.
- `canisotp` — ISO 15765-2: the four frame types, the flow-control
  handshake, `CanIsoTpSession`, the three timers as deadlines the
  caller arms, and extended addressing's one-byte cost.
- `canbus` — error confinement: the two counters, the four states,
  recovery, the error kinds, the standard bit rates and the sample
  point.
- `cantxq` — a bounded transmit queue over heapless-nv that dequeues by
  arbitration priority, with the FIFO order beside it under its own
  name.
- `candump` — the can-utils line and the `cansend` compact form,
  rendered and parsed.
- `canhal` — `CanPeripheral[e]`, `CanTxAccepted`, and which parts carry
  a CAN controller.
- `canerr` — one error type, with `is_transient`.
- `cansocket` — the `host` module: the wire layout `[]`, the socket
  `[net]`, the interface facts `[fs]`.

### Known

- **The load-bearing interface is that a classic CAN frame carries its
  own payload.** Eight bytes is one `Int`, so a frame is three
  integers and every collection of frames in the package is
  allocation-free. CAN FD is where it stops, and `CanFdFrame` is a
  header with the payload left to the caller.
- **The layer is `core` with one `host` module**, not the plan's
  `host`. The subject is the device half.
- **A `@value` struct cannot be a `Result` or optional payload
  (E2015)**, so every fallible answer that would have been
  `Result<CanFrame, CanError>` is a frame carrying its own status:
  `canframe.none()`, `canframe.fault(code)`, and the three predicates.
  `CanTxAccepted` carries a `CAN_TX_*` status for the same reason.
- **A `@value` struct cannot appear in a fn value's signature**, so
  `cantxq`'s selection callbacks take `fn(Int) -> Int` — an
  arbitration key or an identifier — rather than
  `fn(Int) -> CanFrame`. The constraint improved the design: a driver
  already holds its pending identifiers as integers.
- **A `@value` struct cannot be a boxed struct's field**, so
  `candump.CanLogLine` carries the frame's four fields flat and
  `line_frame` assembles one.
- **Neither board this project supports has a CAN controller.**
  `canhal.controller_of` says so for `nrf52840-dk`, `nrf52832-dk` and
  `rp2040`, and the README names the parts that do.
- **The device claim covers `canframe`, `canfilter` and `canisotp`**
  and `tests/embedded_probe.nv` builds them for a Cortex-M4.
- **Two missing rows**: dbc-nv, the CAN database format that turns a
  bit offset into a signal name, and j1939-nv. Neither is on the grid.
- **`cansocket`'s real behaviour needs a `vcan0`**, and the suite has
  nowhere to ask for one — so the socket half is covered by shape
  assertions and the test file says so.
- A peripheral driver, DBC parsing, UDS and J1939 are deliberately
  outside.
