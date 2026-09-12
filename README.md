# can-nv

**Status: NOT IMPLEMENTED — interface only.**

The CAN bus on a microcontroller and on Linux behind one interface:
classic and CAN FD frames as values, acceptance filters and masks, the
error-confinement state machine, a bounded transmit queue that sends by
arbitration priority, ISO-TP segmented transport, a candump-shaped log
line, the `embedded-can` peripheral trait, and SocketCAN over raw
sockets.

Every `pub fn` body is a `todo()`. The signatures and the effect rows
are published so the design can be reviewed and effect-checked before
anyone writes a body against it; `novo pkg add can-nv` resolves,
downloads and builds, and the first call panics with
`not implemented: can-nv.<module>.<fn>`.

## Build, run and test

```bash
novo pkg build          # type-check and effect-check every module; a library, so no binary
novo test               # the API suites — RED until the bodies land
novo doc .              # the reference page, with every example block compiled
```

There is nothing to run: this is a library, and at 0.0.1 every body is
a `todo()`, so `novo test` is red on purpose and the suites are the
protocol written as assertions.

## The one example that will work

Reading an engine-speed frame, on a device and on a laptop, with the
same four lines:

```novo
use canframe
use canfilter

// A filter that accepts the 0x100 block and nothing else — what goes
// into a controller's acceptance registers, and what a receive
// callback evaluates when there are more filters than slots.
let engine = canfilter.filter(0x100, 0x700)

// A frame is three integers: identifier, flags and length in two of
// them, and the whole eight-byte payload in the third.
let f = canframe.frame(0x123, 3, canframe.pack4(0x11, 0x22, 0x33, 0))

if canfilter.accepts(engine, f)
    // Eight bytes fit one Int, so nothing here allocates and this
    // line runs in an interrupt handler on a part with 64 KB of RAM.
    let rpm = canframe.signal_be(canframe.frame_data(f), 0, 16)
```

## The layer, and why

`core`, with one `host` module named in the manifest.

The row's own note is "the bus on a microcontroller and on Linux behind
one interface", and the microcontroller is the half that decides the
layer. The plan placed the row at `host` because SocketCAN is the
visible half; `docs/publishing.md` § A package with a core and a host
half is the shape that fits — the narrow layer declared and the wide
module named — and it is what makes the device claim a thing the audit
**builds**.

- **A device links** `canframe`, `canfilter`, `canisotp`, `canbus`,
  `candump` and `canhal`. All six are `[]` throughout, and
  `tests/embedded_probe.nv` builds the first three for
  `--target=nrf52-qemu`. `cantxq` builds too — heapless-nv makes its
  own device claim — and is left out of the probe only to keep the
  probe's module closure to this package's own sources.
- **A laptop links** `cansocket`, the one module with a row: `[net]`
  for the socket and `[fs]` for the interface index a bind needs.

## The load-bearing interface

**`CanFrame`, and specifically that it carries its own payload.**

A classic CAN frame carries at most eight bytes. Eight bytes is
sixty-four bits. Sixty-four bits is one `Int`. So a whole frame —
identifier, flags, length and payload — is three integers in the
caller's own stack frame, and four things fall out of that:

- a transmit queue moves frames without touching an allocator;
- a filter table is an array of `@value` structs in a `.bss` section;
- a receive interrupt builds a frame and hands it on with no buffer, no
  copy and no lifetime;
- and a test is a table of literals rather than a bus.

A `@value` struct cannot own a buffer (SPEC § 14.3), so the obvious
`data: [u8]` field would have made the frame a boxed struct and every
one of those four false. The protocol's own limit is what makes the
constraint free.

**CAN FD is where the trick stops**, and the package says so rather
than pretending otherwise. An FD frame carries up to 64 bytes, which is
eight `Int`s, and a `@value` struct of eight payload words would be
copied whole on every assignment. So `CanFdFrame` is the header alone
and the payload stays in the caller's buffer — which, for a driver with
a 64-byte DMA region, is where it already is.

**The second load-bearing value is `arbitration_key`.** CAN arbitration
is bitwise and dominant-low, so the numerically *smaller* identifier
wins the bus. Packing the identifier, the extension bit and the remote
bit into one integer makes `<` the comparison the bus performs — and
that is what lets `cantxq` hand over the frame that would win rather
than the one that arrived first. A FIFO transmit queue throws away the
one real-time guarantee CAN offers, and nothing inside a FIFO can
notice.

## The reference implementations

[`embedded-can`](https://docs.rs/embedded-can) for the peripheral trait
— `CanPeripheral[e]` is its shape with an effect parameter — and
[SocketCAN](https://docs.kernel.org/networking/can.html) for the host
half, including its `struct can_frame` layout, its `can_filter` with
the `CAN_INV_FILTER` bit, and the `candump` and `cansend` text formats
from [can-utils](https://github.com/linux-can/can-utils). The protocol
itself is ISO 11898-1; the segmented transport is ISO 15765-2.

## What is here

| Module | Layer | What it is |
| --- | --- | --- |
| `canframe` | `core` | Classic and FD frames as `@value` records, the identifier widths, the data length codes, the arbitration key, and the signal arithmetic. |
| `canfilter` | `core` | Acceptance filters and masks, evaluation, and the merge that fits more filters than the hardware has slots. |
| `canisotp` | `core` | ISO 15765-2: the four frame types, the flow-control handshake, the session, and four timers as deadlines the caller arms. |
| `canbus` | `core` | Error confinement: the two counters, the four states, recovery, and the bit timing a clock can or cannot produce. |
| `cantxq` | `core` | A bounded transmit queue over heapless-nv that dequeues by arbitration priority. |
| `candump` | `core` | The can-utils log line and the `cansend` compact form, rendered and parsed. |
| `canhal` | `core` | `CanPeripheral[e]`, what a transmit attempt answers, and which parts have a controller. |
| `canerr` | `core` | One error type, with `is_transient` as the distinction a retry loop needs. |
| `cansocket` | `host` | SocketCAN: the wire layout `[]`, the socket `[net]`, the interface facts `[fs]`. |

## Three things the design decided, and why

**A fallible answer is a frame that carries its own status.** A
`@value` struct cannot be an optional or a `Result` payload (E2015), so
`receive` cannot answer `Result<?CanFrame, CanError>`. It answers a
`CanFrame`, and `canframe.is_none`, `canframe.is_fault` and
`canframe.is_frame` are the three questions. A receive loop's first
line is `if canframe.is_none(f) break` either way, so the shape costs a
caller nothing — and `is_frame` exists so that a caller who checks only
one of the two halves is not silently treating a refusal as a frame on
identifier 3.

**A callback answers an integer, not a frame.** A `@value` struct
cannot appear in a fn value's signature either, so `cantxq`'s selection
functions take `key_at: fn(Int) -> Int` rather than
`frame_at: fn(Int) -> CanFrame`. That turned out better than what it
replaced: a driver keeps its pending identifiers in a parallel array
because that is what it programmed into the mailbox registers, and it
never has to reconstruct a frame to answer.

**A node alone on a bus goes bus-off in thirty-two frames**, and
`canbus.would_go_bus_off_alone` says so as a number rather than a
paragraph. With no peer to acknowledge, every transmission is an
acknowledgement error; eight up and one down reaches 256 in
thirty-two. It is the single most common first experience of CAN — a
board on a bench with a terminator and no second node — and a
diagnostic that can state it saves an afternoon.

## Which boards have a CAN controller

**Neither of the two this project supports.** The nRF52840 has none and
the RP2040 has none; what those parts need is an external MCP2515 (or
MCP2518FD for FD) over SPI, which is a driver over `orbit/hal`'s SPI
trait rather than anything this package supplies. `canhal.controller_of`
answers `CAN_CONTROLLER_NONE` for all three of `nrf52840-dk`,
`nrf52832-dk` and `rp2040`, so a firmware build can fail with a name in
the message rather than on a bench.

The parts with one on the die are STM32 (bxCAN on the F1/F4/L4, FDCAN
on the G0/G4/H7/U5), NXP's FlexCAN (i.MX RT, S32K, LPC), the ESP32's
TWAI, Atmel SAM C/E and Infineon AURIX.

## What is deliberately outside

- **A peripheral driver.** Nothing here writes a register or drives a
  chip select. That belongs with the board.
- **DBC files.** `canframe.signal_be` and `signal_le` are the
  arithmetic a decoded signal needs; the file format that describes
  which signals a bus carries is a parser, and it is a missing row —
  see below.
- **UDS and J1939.** Both sit *on* ISO-TP rather than in it. J1939 in
  particular redefines the 29-bit identifier as a structured field, and
  that is a package of its own.
- **CAN FD payload buffers.** The header is a value and the bytes are
  the caller's, on purpose.

## Missing rows this package found

- **dbc-nv** (`core`/`embedded`): the CAN database format — messages,
  signals with their bit offsets, scale and offset, value tables. It is
  what turns `signal_be(data, 0, 16)` into "engine speed in rpm", every
  automotive tool reads it, and nothing on the grid names it.
- **j1939-nv** (`core`/`embedded`): the identifier structure, the
  transport protocol and the address claim, over this package.
- **A `vcan` fixture for the umbrella suite.** `cansocket`'s real
  behaviour needs `ip link add dev vcan0 type vcan`, and the suite has
  nowhere to say "this test needs a virtual interface". Without one,
  the socket half stays covered by shape assertions only, which this
  package's own test file says out loud.

## Licence

Apache-2.0.
