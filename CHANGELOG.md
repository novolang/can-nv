# Changelog

All notable changes to can-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

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
