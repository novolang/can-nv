# can-nv

The Controller Area Network (CAN) is a two-wire serial bus on which every
node may start a message at any time, and a message carries an identifier
rather than an address. It is specified in ISO 11898-1, and it is what a car,
a machine tool and an industrial drive use to talk to their own parts. This
package brings the protocol to novo-lang: the frames, the acceptance filters,
the error-confinement rules, the segmented transport of ISO 15765-2, the
`candump` text format, and Linux's SocketCAN interface.

**Status: NOT IMPLEMENTED — interface only.** Every function is declared with
its full signature, but every body is a `todo()` that panics when called. The
package is published so its design can be reviewed and depended on before it
is implemented. Version 0.1.0 will be the first working release.

## What CAN is

A **frame** is one message on the bus. It carries an **identifier**, a length
and up to eight bytes of data. Nothing in the frame says who sent it or who
should read it. Every node sees every frame and decides, from the identifier
alone, whether the frame is one it cares about.

The identifier comes in two widths. The **standard** identifier is 11 bits.
The **extended** identifier is 29 bits, and a frame using it sets a bit that
says so.

**Arbitration** is how two nodes that start at the same moment settle it. The
bus is wired so that a zero bit sent by any node overrides a one bit sent by
another. Both nodes transmit their identifiers and watch the wire. The first
node to send a one and read back a zero has lost, stops, and retries later.
The numerically smaller identifier therefore always wins, and it wins without
a collision and without losing a bit time. A smaller identifier is a
higher-priority message.

An **acceptance filter** is a pair of numbers a controller is programmed
with: a value and a **mask**. The mask says which bits of an incoming
identifier are compared. A filter of value 0x100 and mask 0x700 accepts
every identifier from 0x100 to 0x1FF. Hardware filters exist because a busy
bus carries thousands of frames a second and a node wants perhaps five of
them.

**Error confinement** is how a broken node takes itself off the bus. Each
node keeps two counters. A transmit error adds eight to the transmit counter
and a receive error adds one to the receive counter, and a success subtracts
one from whichever applies. Crossing 128 makes a node **error-passive**,
which means it may no longer signal an error to the others. A transmit
counter reaching 256 makes it **bus-off**, which means it stops transmitting
altogether until it is reset and has seen 128 occurrences of eleven
consecutive idle bits.

**CAN FD** is the later flexible-data-rate form of the same bus. An FD frame
carries up to 64 bytes and may switch to a faster bit rate for the data
part.

**ISO-TP**, specified in ISO 15765-2, carries a message longer than one
frame. It has four frame types. A **single frame** holds the whole message. A
longer message starts with a **first frame**, then waits for a **flow
control** frame from the receiver saying how many frames it will take and how
fast, then sends **consecutive frames** numbered 0 to 15 and wrapping. The
flow control frame is what lets a microcontroller stop a diagnostic tool from
sending four kilobytes at bus speed.

| Quantity | Value |
| --- | --- |
| Data bytes in a classic frame | 0 to 8 |
| Data bytes in an FD frame | 0 to 64 |
| Standard identifier | 11 bits, 0 to 0x7FF |
| Extended identifier | 29 bits, 0 to 0x1FFFFFFF |
| Transmit error weight, receive error weight | 8, 1 |
| Error-passive limit, bus-off limit | 128, 256 |
| Idle sequences before a bus-off node may rejoin | 128 |
| Frames to bus-off for a node alone on the bus | 32 |
| ISO-TP single frame payload | 7 bytes |
| ISO-TP first frame payload | 6 bytes |
| ISO-TP consecutive frame payload | 7 bytes |
| Longest ISO-TP message | 4095 bytes |
| Standard bit rates this package knows | 9 |

## Install

```
novo pkg add can-nv
```

## Example

```novo
use canframe
use canfilter

fn main() [io]
    // Accept identifiers 0x100 to 0x1FF and nothing else. The mask says
    // which bits of an incoming identifier are compared against 0x100.
    let engine = canfilter.filter(0x100, 0x700)

    // A frame is three integers: the identifier, the flags and length,
    // and the whole eight-byte payload packed into the third.
    let f = canframe.frame(0x123, 3, canframe.pack4(0x11, 0x22, 0x33, 0))

    if canfilter.accepts(engine, f)
        // Sixteen bits starting at bit 0 of the payload, most significant byte
        // first. Nothing allocates, so this line runs in an interrupt handler.
        let rpm = canframe.signal_be(canframe.frame_data(f), 0, 16)
        println("${rpm}")
```

Build and test with `novo pkg build` and `novo test`. Today `novo test` fails
on purpose: every test reaches a `not implemented: can-nv.<module>.<fn>`
panic. The tests are the specification the implementation will have to
satisfy.

## What the package contains

| Module | Contents |
| --- | --- |
| `canframe` | Classic and FD frames as values, both identifier widths, remote and error frames, the data length codes, the arbitration key, and the arithmetic that reads a numeric signal out of a payload. |
| `canfilter` | Acceptance filters and masks, the test of a frame against one, and the merge that fits more filters than a controller has slots. |
| `canisotp` | ISO 15765-2: the four frame types, the flow-control handshake, a session value, and three timers as deadlines the caller arms. |
| `canbus` | Error confinement: the two counters, the four states, recovery, the error kinds, the standard bit rates and the sample point. |
| `cantxq` | A bounded transmit queue that hands over the frame that would win arbitration, not the frame that arrived first. |
| `candump` | The can-utils log line and the `cansend` compact form, rendered and parsed. |
| `canhal` | `CanPeripheral[e]`, the trait a controller driver satisfies, what a transmit attempt answers, and which parts have a controller on the die. |
| `canerr` | One error type, with the question a retry loop asks of it. |
| `cansocket` | SocketCAN on Linux: the kernel's frame layout, the socket, and the interface facts a bind needs. |

## How to choose an entry point

**A device links everything except `cansocket`.** Those eight modules declare
no effects. They are arithmetic over values the caller holds.

**A Linux program links `cansocket` as well.** It is the one module that
performs anything: `[net]` for the socket and `[fs]` for an interface's
kernel index, which a bind needs and a socket cannot answer.

**`canhal.CanPeripheral[e]` is the seam between the two.** A board's driver
satisfies it on a device and `cansocket` satisfies it on Linux, and the rest
of the package is written against neither.

**Use `canframe` and `canfilter` alone for the common receive path.** Build a
frame, test it against a filter, read a signal out of it. Reach for
`canisotp` only when a message is longer than eight bytes, and for `cantxq`
only when more frames are queued than the controller has mailboxes.

## The rules a user needs

1. **A classic frame carries its own payload; an FD frame does not.** Eight
   bytes is sixty-four bits, so `CanFrame` is three integers and costs
   nothing to copy. An FD frame's 64 bytes would be eight integers copied on
   every assignment, so `CanFdFrame` is the header and the bytes stay in the
   caller's buffer, which for a driver with a DMA region is where they
   already are.
2. **A smaller identifier wins the bus.** `canframe.arbitration_key` packs the
   identifier, the extension bit and the remote bit into one integer so that
   `<` is the comparison the bus performs, and `canframe.wins_arbitration`
   asks it directly.
3. **A transmit queue that sends in arrival order throws away CAN's
   real-time guarantee.** `cantxq.dequeue_index` picks by arbitration
   priority. `cantxq.dequeue_fifo_index` is the arrival order, under its own
   name, for a caller who wants it.
4. **A receive answers a frame that carries its own status, not an optional
   or a `Result`.** A `@value` struct may not be an optional or a `Result`
   payload (E2015). `canframe.none()` means nothing arrived and
   `canframe.fault(code)` means something was refused. Ask
   `canframe.is_frame` before reading an identifier, because `is_none` alone
   would treat a refusal as a frame on identifier 3.
5. **A selection callback takes an integer, not a frame.** A `@value` struct
   may not appear in a function value's signature, so `cantxq`'s callbacks
   are `fn(Int) -> Int` over an arbitration key. A driver already holds its
   pending identifiers as integers, because that is what it programmed into
   the mailbox registers.
6. **A bus error is not a program error.** A node alone on a bus produces an
   acknowledgement error on every frame it sends, for ever, and that is the
   protocol working. Those belong to `canbus`'s counters and states, not to
   `canerr`.
7. **A node alone on a bus goes bus-off after thirty-two frames.** Eight up
   per error and one down per success reaches 256 in thirty-two attempts.
   `canbus.would_go_bus_off_alone` says so, and it is the first thing to
   check when a board on a bench with a terminator and no second node stops
   transmitting.
8. **Two nodes with different sample points work until the cable gets
   longer.** CiA 301 asks for 87.5 per cent at 500 kbit/s and above and 75
   per cent below it. `canbus.sample_point_permille` answers the figure in
   tenths of a per cent, and `canbus.check_timing` answers whether a given
   clock can produce it.
9. **An ISO-TP receiver decides the pace, and the sender must obey it.** The
   flow control frame carries a block size and a minimum separation time, and
   `canisotp.session` tracks both. ISO 15765-2 caps a message at 4095 bytes
   in the form this package implements.
10. **Consecutive frame numbers wrap at 16.** `canisotp.next_index` applies
    the rule. A receiver that does not check the number cannot tell a lost
    frame from a late one.
11. **Extended addressing costs one payload byte per frame.**
    `canisotp.addressing_overhead`, `single_max` and `consecutive_max`
    answer the reduced figures, so a caller never subtracts by hand.
12. **A filter with the inverted flag rejects what it matches.** SocketCAN
    spells the same thing `CAN_INV_FILTER`. `canfilter.merge` combines two
    filters into one that a controller slot can hold, and
    `canfilter.false_accept_width` says how many identifiers the merged
    filter lets through that neither original did.

## Running on a microcontroller

The package states that its modules run on a device with no heap allocator,
and the compiler checks that claim on every build. Eight of the nine modules
carry no effects and are inside the claim: `canframe`, `canfilter`,
`canisotp`, `canbus`, `cantxq`, `candump`, `canhal` and `canerr`.

`tests/embedded_probe.nv` is that claim as a program that either builds or
does not. It covers `canframe`, `canfilter` and `canisotp`, which is the
receive path an interrupt handler runs.

```bash
novo build --target=nrf52-qemu tests/embedded_probe.nv
```

That command was run against this release. It produces a Cortex-M4
executable, `embedded_probe.elf`. The probe builds; it is not run, because
every function it calls is a `todo()` that would panic on the first line.

`cansocket` is outside the claim. It names `std.net`, and one host-only
function anywhere in a compilation unit is an undefined symbol at link time
on a device, whether or not the firmware calls it.

**Neither board this project supports has a CAN controller.** The nRF52840
has none and the RP2040 has none. Those parts need an external MCP2515, or an
MCP2518FD for CAN FD, driven over SPI, which is a board's driver rather than
anything this package supplies. `canhal.controller_of` answers
`CAN_CONTROLLER_NONE` for `nrf52840-dk`, `nrf52832-dk` and `rp2040`, so a
firmware build fails with a name in the message rather than on a bench. The
parts with a controller on the die are STM32 (bxCAN on the F1, F4 and L4;
FDCAN on the G0, G4, H7 and U5), NXP's FlexCAN in the i.MX RT, S32K and LPC
families, the ESP32's TWAI, Atmel SAM C and E, and Infineon AURIX.

## What is not included

- **A peripheral driver.** No function here writes a register or drives a
  chip select. That belongs with the board.
- **CAN database files.** The `.dbc` format names the signals a bus carries
  and gives each one a scale and an offset. `canframe.signal_be` and
  `signal_le` are the arithmetic underneath it, and the parser is a package
  that does not exist yet.
- **UDS and J1939.** Both sit on ISO-TP rather than in it. J1939 redefines
  the 29-bit identifier as a structured field, which makes it a package of
  its own.
- **A buffer for an FD payload.** The header is a value and the bytes are the
  caller's. See rule 1.
- **A test against a real bus.** `cansocket`'s behaviour needs a virtual CAN
  interface created with `ip link add dev vcan0 type vcan`, and the test
  suite has no way to ask for one. The socket half is covered by assertions
  about shape only, and its test file says so.

## Related packages

- [heapless-nv](https://novo-lang.org/packages/heapless-nv) is the
  fixed-capacity containers this package's transmit queue is built on. A
  bounded queue on a device needs storage that is not the heap.
- [bitfield-nv](https://novo-lang.org/packages/bitfield-nv) describes a
  hardware register's bits. A driver for an external CAN controller
  configures it through registers, and that is where the descriptions go.
- [modbus-nv](https://novo-lang.org/packages/modbus-nv) is the other
  industrial fieldbus on the registry. Modbus is a request and a reply
  between a client and a server. CAN is a broadcast with no addresses in it.
- `std.net` in the standard library is the sockets `cansocket` opens.

## Tests

```bash
novo test                             # 134 tests
novo test tests/canframe_tests.nv     # 19: the frame, the identifiers, the signals
novo test tests/canfilter_tests.nv    # 13: acceptance, inversion, merging
novo test tests/canisotp_tests.nv     # 21: the four frame types and the handshake
novo test tests/canbus_tests.nv       # 15: the counters, the states, the timing
novo test tests/cantxq_tests.nv       # 13: priority order against arrival order
novo test tests/canreaders_tests.nv   # 14: the candump line, both directions
novo test tests/canhost_tests.nv      # 28: the peripheral trait and the wire layout
novo test tests/cansocket_tests.nv    # 11: the socket surface, by shape
```

The references are ISO 11898-1 for the protocol, ISO 15765-2 for the
segmented transport, [embedded-can](https://docs.rs/embedded-can) for the
peripheral trait, and
[SocketCAN](https://docs.kernel.org/networking/can.html) for the kernel's
frame and filter layouts. The text formats are `candump`'s and `cansend`'s,
from [can-utils](https://github.com/linux-can/can-utils).

No test opens a socket or reads a clock. Every frame is a literal, every
deadline is an argument, and a whole ISO-TP exchange is a list of values the
test writes out.

The tests compile today and fail at run, each on the
`not implemented: can-nv.<module>.<fn>` panic that is its body. That is the
expected state of an interface release. They turn green one at a time as
bodies land.

## Implementation status

| Item | Implemented |
| --- | --- |
| Every `CAN_*` constant in `canframe`, `canfilter`, `canisotp`, `canbus`, `canhal`, `cansocket` | yes (they are constants) |
| `canframe.CanFrame`, `.CanFdFrame`, `canfilter.CanFilter`, `canisotp.CanIsoTpSession`, `canbus.CanBusState`, `cantxq.CanTxQueue`, `canhal.CanTxAccepted`, `candump.CanLogLine`, `canerr.CanError`, `cansocket.CanSocket` | declared |
| `canhal.CanPeripheral[e]` | declared |
| `canframe`: the constructors, the accessors, the packing, the arbitration key and the signal arithmetic | no |
| `canfilter`: the constructors, `accepts`, `merge`, `covers`, `false_accept_width` | no |
| `canisotp`: the frame builders, the readers, the session and the timers | no |
| `canbus`: the counters, the states, recovery, the bit rates and the timing check | no |
| `cantxq`: the queue, both dequeue orders and the displacement rules | no |
| `candump`: rendering and parsing both formats | no |
| `canhal`: the transmit result, the three helpers and the controller table | no |
| `canerr.describe`, `.is_transient` | no |
| `cansocket`: the wire layout, the socket and the interface facts | no |

## Licence

Apache-2.0. See `LICENSE`.

<!-- docs/writing-a-readme.md is the style guide for this page. -->
