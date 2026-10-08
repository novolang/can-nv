# can-nv

The Controller Area Network (CAN) is a two-wire serial bus on which every
node may start a message at any time, and a message carries an identifier
rather than an address. It is specified in ISO 11898-1, and it is what a car,
a machine tool and an industrial drive use to talk to their own parts. This
package brings the protocol to novo-lang: the frames, the bit timing, the
acceptance filters, the error-confinement rules, drivers for the two STM32
CAN controllers, the segmented transport of ISO 15765-2, the `candump` text
format, and Linux's SocketCAN interface.

## What CAN is

A **frame** is one message on the bus. It carries an **identifier**, a length
and up to eight bytes of data. Nothing in the frame says who sent it or who
should read it. Every node sees every frame and decides, from the identifier
alone, whether the frame is one it cares about.

The identifier comes in two widths. The **standard** identifier is 11 bits.
The **extended** identifier is 29 bits, and a frame using it sets a bit that
says so. A **remote frame** asks another node to send the frame with its
identifier, and carries no data.

**Arbitration** is how two nodes that start at the same moment settle it. A
zero bit sent by any node overrides a one bit sent by another, so the
numerically smaller identifier wins, without a collision and without losing
a bit time (ISO 11898-1 section 10.4.2.2). A smaller identifier is a
higher-priority message.

**Bit timing** is how a controller divides one bit into **time quanta**, each
a fixed number of its clock cycles. A bit is one synchronisation quantum,
then a first segment, then a second; the bus is sampled between the two
segments, at the **sample point**. Every node on a bus must use the same bit
rate and nearly the same sample point.

An **acceptance filter** is what a controller is programmed with to decide
which identifiers to receive. A **mask filter** is a value and a **mask**:
the mask says which bits of an incoming identifier are compared, so a value
of 0x100 and a mask of 0x700 accepts 0x100 to 0x1FF. A **list filter** names
identifiers exactly, two to a filter slot.

**Error confinement** is how a broken node takes itself off the bus. Each
node keeps a transmit and a receive error counter. A transmit error adds
eight and a receive error one, and a success subtracts one. At 128 a node is
**error-passive**; a transmit counter of 256 makes it **bus-off**, and it
sends nothing until it is reset and has seen 128 sequences of eleven idle
bits (ISO 11898-1 section 12.1.4).

**CAN FD** is the later flexible-data-rate form of the same bus. An FD frame
carries up to 64 bytes and may switch to a faster bit rate for the data part,
the **bit rate switch** (BRS).

**ISO-TP**, specified in ISO 15765-2, carries a message longer than one
frame: a **first frame**, a **flow control** frame from the receiver saying
how many frames it will take and how fast, then **consecutive frames**
numbered 0 to 15 and wrapping.

| Quantity | Value |
| --- | --- |
| Data bytes in a classic frame | 0 to 8 |
| Data bytes in an FD frame | 0 to 8, 12, 16, 20, 24, 32, 48, 64 |
| Standard identifier | 11 bits, 0 to 0x7FF |
| Extended identifier | 29 bits, 0 to 0x1FFFFFFF |
| Transmit error weight, receive error weight | 8, 1 |
| Error-warning, error-passive, bus-off limits | 96, 128, 256 |
| Frames to bus-off for a node alone on the bus | 32 |
| Idle sequences before a bus-off node may rejoin | 128 |
| Longest ISO-TP message | 4095 bytes |

## Install

```
novo pkg add can-nv
```

## Example

This program runs FDCAN1 of an STM32H723 in its internal loopback mode, in
which a frame sent is received by the same controller, so no transceiver
and no second node are needed. It sends one classic frame and reads it back.

```novo norun:needs-pkg
use canframe
use canbus
use canhal
use canfdcan

fn main() [hw, mutate]
    bsp.board.init()
    // FDCAN's kernel clock is the board's 8 MHz HSE.
    canfdcan.h7_clock_on(canfdcan.FDCAN_CLOCK_HSE)
    // 500 kbit/s with the sample point at 87.5 per cent, and a 2 Mbit/s
    // data phase at 75 per cent.
    let nominal = canbus.solve_timing(8000000, 500000, 875, canbus.fdcan_nominal_limits())
    let data = canbus.solve_timing(8000000, 2000000, 750, canbus.fdcan_data_limits())
    let can = canfdcan.fdcan1()
    if not canfdcan.start(can, nominal, data, true, canfdcan.FDCAN_MODE_INTERNAL_LOOPBACK)
        hal.uart.write("FDCAN1 did not start\n")
        return
    // A frame on identifier 0x123 with three bytes.
    let sent = canhal.transmit_checked(can, canframe.frame(0x123, 3, canframe.pack4(0x11, 0x22, 0x33, 0)))
    for _i in 0..100000
        // The loopback delivers the frame to the receive FIFO.
        let f = can.can_receive()
        if canframe.is_frame(f)
            if canframe.frame_byte(f, 2) == 0x33
                hal.uart.write("received 0x123\n")
            return
```

`examples/embedded/can_demo` in the novo-lang repository holds three longer
programs: the same session over the loopback controller on every board and
under QEMU, over FDCAN on the NUCLEO-H723ZG, and over bxCAN on the
STM32F407G-DISC1.

## What the package contains

| Module | Contents |
| --- | --- |
| `canframe` | Classic frames with their payload, FD frame headers, both identifier widths, remote and error frames, the data length codes, the arbitration key, and reading a numeric signal out of a payload. |
| `canfilter` | Mask and list filters, the test of a frame against one, inversion, and the merge that fits more filters than a controller has slots. |
| `canbus` | Error confinement: the counters, the four states and recovery.  The standard bit rates, the sample point, and the bit-timing solver with each controller's limits. |
| `canhal` | `CanPeripheral[e]`, the trait every controller satisfies, and `CanFdPeripheral[e]`, its CAN FD half; what a transmit answers; which parts have a controller. |
| `canbxcan` | The driver for ST's bxCAN (STM32F1, F2, F3, F4, F7, L4): mailboxes, the filter banks, the modes, bus-off recovery. |
| `canfdcan` | The driver for ST's FDCAN, Bosch's M_CAN (STM32H7): the message RAM, classic and FD frames, the filter elements, the modes, bus-off recovery. |
| `canboard` | `CanBoard`, the board's CAN controller behind `CanPeripheral[hw]`, over embedded-hal-nv's `CanBus` and `BoardCan`: one mailbox, the counters, the trait's refusals for what `CanBus` cannot do. |
| `canloop` | A controller in memory that receives what it sends, with mailboxes, a receive FIFO, filters and the error counters, for tests and emulators. |
| `cantxq` | A transmit queue over the caller's frames that hands over the frame that would win arbitration. |
| `canring` | A receive ring over the caller's frames. |
| `canisotp` | ISO 15765-2: the four frame types, the flow-control handshake, a session value, and the timers as deadlines the caller arms. |
| `candump` | The can-utils log line and the `cansend` compact form, rendered and parsed. |
| `canerr` | One error type, with the question a retry loop asks of it. |
| `cansocket` | SocketCAN on Linux: the kernel's frame layout, the socket, the kernel's filters, and what sysfs says about an interface. |

## How to choose an entry point

**A program on a board** whose board serves `hal.can` opens its
controller with `canboard.board_open(0, bitrate, loopback)` and talks to it
through `CanPeripheral`, with no driver of this package's own; the
FRDM-MCXN947's CAN0 is one.  On an STM32 board without `hal.can`, it
starts the controller with `canbxcan.start` or `canfdcan.start`.  The same
code runs over each of them and over `canloop`.

**A test or an emulated board** uses `canloop`, which needs no hardware and
behaves like a controller in loopback mode.

**A program on Linux** uses `cansocket`. A virtual interface, `vcan0`, needs no
hardware.

**`canframe` and `canfilter` alone** are the common receive path: build a
frame, test it against a filter, read a signal out of it. Reach for
`cantxq` when more frames wait than the controller has mailboxes, for
`canring` when frames arrive faster than the program services the
controller, and for `canisotp` when a message is longer than one frame.

## The rules a user needs

1. **A classic frame carries its own payload; an FD frame does not.** Eight
   bytes fit one `Int`, so `CanFrame` is four integers and costs nothing to
   copy. `CanFdFrame` is the header; the up to 64 bytes are a `Vec[u8; 64]`
   the caller holds, which `can_transmit_fd` reads and `can_receive_fd` fills.
2. **A smaller identifier wins the bus.** `canframe.arbitration_key` is one
   integer whose order is the bus's order, extended frames and remote frames
   included. The first eleven bits of a 29-bit identifier are its top
   eleven, so `0x123 << 18` is the extended identifier that shares 0x123's.
3. **A transmit answers a mailbox, not completion.** `can_tx_done` says when
   the frame has left. When every mailbox is full, a frame that outranks a
   pending one displaces it, and `accepted_displaced` names the mailbox, so
   the caller can queue that frame again.
4. **A receive answers a frame that carries its own status.**
   `canframe.none()` means nothing arrived and `canframe.fault(code)` means
   something was refused. Ask `canframe.is_frame` before reading an
   identifier.
5. **A node alone on a bus goes bus-off after 32 frames.** With no other
   node to acknowledge, every transmission is an error. `canbus.would_go_bus_off_alone`
   says so, and it is the first thing to check when a board on a bench stops
   transmitting.
6. **Recovery cancels what is pending.** `can_recover` on either driver
   aborts the frames waiting in the mailboxes before the controller rejoins,
   so a stale command is not sent late. `cantxq.cleared` does the same for
   the software queue.
7. **Two nodes need the same bit rate and nearly the same sample point.**
   CiA 301 asks for 87.5 per cent at 500 kbit/s and above and 75 per cent
   below it; `canbus.sample_point_permille` answers it. `canbus.solve_timing`
   refuses a clock that cannot produce the rate to within 0.1 per cent.
8. **An FD length is not every number.** 9 to 11, 13 to 15 and the other gaps
   above 8 do not exist; a payload is padded to the next length the format
   has, and `canframe.fd_len_is_valid` and `fd_padded_len` say which.
9. **A filter with bits outside its mask is refused.** Those bits are never
   compared, so the filter accepts more than it says. `canfilter.check_filter`
   answers the refusal.
10. **A controller's hardware cannot hold every filter.** Neither driver
    holds an inverted filter; FDCAN's remote-frame setting is one switch for
    all filters. `canfilter.merge` widens two filters into one slot and
    `false_accept_width` says how many identifiers the widening lets in.
11. **An ISO-TP receiver decides the pace.** The flow control frame carries a
    block size and a minimum separation time, and consecutive frame numbers
    wrap at 16 (ISO 15765-2 section 9.6).

## Bit timing

`canbus.solve_timing(clock_hz, bitrate, sample_permille, limits)` tries
every prescaler the controller allows, places the sample point as near the
target as the segment limits allow, and keeps the timing whose bit rate is
nearest, then whose sample point is nearest, then with the most quanta. The
limits are values: `bxcan_limits`, `fdcan_nominal_limits` and
`fdcan_data_limits`. `canbxcan.btr_of`, `canfdcan.nbtp_of` and `dbtp_of`
give the register words.

| Controller and clock | Rate | Prescaler | Quanta | Segments | Sample point | Register |
| --- | ---: | ---: | ---: | --- | ---: | --- |
| bxCAN, 42 MHz (STM32F4 APB1) | 500 kbit/s | 6 | 14 | 1 + 11 + 2 | 85.7 % | CAN_BTR 0x001A0005 |
| bxCAN, 42 MHz | 1 Mbit/s | 3 | 14 | 1 + 11 + 2 | 85.7 % | CAN_BTR 0x001A0002 |
| FDCAN, 8 MHz (NUCLEO-H723ZG HSE) | 500 kbit/s | 1 | 16 | 1 + 13 + 2 | 87.5 % | FDCAN_NBTP 0x02000C01 |
| FDCAN, 8 MHz | 1 Mbit/s | 1 | 8 | 1 + 6 + 1 | 87.5 % | FDCAN_NBTP 0x00000500 |
| FDCAN data phase, 8 MHz | 2 Mbit/s | 1 | 4 | 1 + 2 + 1 | 75 % | FDCAN_DBTP 0x00000100 |
| FDCAN, 80 MHz | 500 kbit/s | 1 | 160 | 1 + 139 + 20 | 87.5 % | — |

The bxCAN rows are the values CAN in Automation's bit-timing calculator and
ST's application notes give; the synchronisation jump width is one quantum
for classic timing and the whole second segment for FDCAN, as CiA 601-3
recommends.

## Running on a microcontroller

Everything a device build reaches performs at most `[hw, mutate]`, and the
frames, filters, timing and state machines perform nothing. After start-up
nothing is allocated: a frame, a filter, a session and a driver handle are
`@value` structs in the caller's frame, the queue and the ring are
bookkeeping over the caller's `Vec[CanFrame; N]`, and the loopback
controller's state is static storage. Building a refusal with a payload,
`Some(CanIdTooWide(…))`, is a heap cell, so the functions that answer one
are `@tier(rt)`; the receive and transmit paths answer status codes instead.

| Value | Bytes, inline |
| --- | ---: |
| `CanFrame` | 32 |
| `CanFdFrame`, `CanFilter`, `CanBusState`, `CanTxAccepted` | 24 |
| `CanTxQueue`, `CanRxRing` | 32 |
| `CanIsoTpSession` | 56 |
| `CanBitTiming` | 48 |
| `BxCan`, `FdCan`, `CanLoop` | 24, 16, 8 |
| `canloop`'s state in `.bss` | 1,000 |
| `Vec[u8; 64]`, an FD payload | 72 |

The drivers take a handle that holds the controller's base address, so the
handle is the same on every board of a family:

| Board | Controller | Instances | Pins brought out | Transceiver |
| --- | --- | --- | --- | --- |
| STM32F407G-DISC1 | bxCAN | CAN1 at 0x40006400, CAN2 at 0x40006800 | CAN1 on PD0 (RX) and PD1 (TX), or PB8 and PB9 | none |
| NUCLEO-H723ZG | FDCAN | FDCAN1 at 0x4000A000, FDCAN2 at 0x4000A400, message RAM at 0x4000AC00 | FDCAN1 on PD0 (RX) and PD1 (TX) | none |

`canbxcan.f4_route_pd0_pd1` and `canfdcan.h7_route_pd0_pd1` put the
controllers on those pins. A real bus needs a transceiver between the pins
and the wires; the loopback modes need neither.

`canhal.controller_of` answers `CAN_CONTROLLER_NONE` for the nRF52, nRF53,
RP2040 and RP2350 boards. Those parts need an external controller over SPI,
the MCP2515 or the MCP2518FD, which this package does not drive.

`cansocket` builds only for a host, at `@tier(app)`, and `candump` renders
text at `@tier(rt)`.

## What is not included

- **Drivers for other controllers.** FlexCAN, TWAI, the MCP2515 and the
  MCP2518FD have no driver here; `CanPeripheral` is the trait one would
  satisfy.
- **Interrupts.** The drivers poll; a program services the controller from
  its loop. A receive interrupt handler can call `can_receive` itself.
- **A real bus on the bench.** The drivers' normal mode is exercised only
  without a transceiver, where every frame is an error; the loopback modes
  exercise the rest.
- **CAN database files.** The `.dbc` format names a bus's signals.
  `canframe.signal_be` and `signal_le` are the arithmetic underneath it.
- **UDS and J1939.** Both sit on ISO-TP rather than in it.
- **The controller counters and bit rate on Linux.** The kernel reports a
  controller's error counters and bit rate over netlink, which `cansocket`
  does not read; `interface_tx_errors` and `interface_rx_errors` answer the
  interface's error statistics from sysfs, and `interface_bitrate` answers
  -1.

## Related packages

- [modbus-nv](https://novo-lang.org/packages/modbus-nv) is the other
  industrial fieldbus on the registry. Modbus is a request and a reply
  between a client and a server. CAN is a broadcast with no addresses in it.
- [shell-nv](https://novo-lang.org/packages/shell-nv) is a device console;
  a program can register commands that send and dump frames.
- `std.net` in the standard library holds the SocketCAN calls `cansocket`
  is written over: `net.can_open`, `net.can_set_option` and
  `net.can_recv_from`.

## Tests

```bash
novo test tests/canframe_tests.nv     # 27: the frame, the identifiers, arbitration, the signals
novo test tests/canfilter_tests.nv    # 22: acceptance, lists, inversion, merging
novo test tests/canbus_tests.nv       # 18: the counters, the states, the timing check
novo test tests/cantiming_tests.nv    # 13: the solver against published values, the register words
novo test tests/cantxq_tests.nv       # 16: priority order against arrival order
novo test tests/canisotp_tests.nv     # 32: the four frame types and the handshake
novo test tests/canhost_tests.nv      # 28: candump, the wire layout, the peripheral trait
novo test tests/candump_tests.nv      # 10: candump lines and their refusals
novo test tests/canhal_tests.nv       #  5: the peripheral trait's helpers over the loopback controller
novo test tests/canreaders_tests.nv   # 14: the readers, both directions
novo test tests/cansocket_tests.nv    # 16: the socket surface on a machine with no CAN interface
novo test tests/canloop_tests.nv      # 16: a controller in memory, the ring and the queue behind it
novo test tests/candriver_tests.nv    #  5: the drivers' handles, words and message RAM layout
novo test tests/canboard_tests.nv     # 11: the device half over a CanBus double, and over a host's absent controller
```

The suites run every line of `src/` on a host but for the regions a
`cov: skip` marker names with its reason: the bxCAN and FDCAN drivers'
register access, which only a board maps, and the paths of `cansocket`
that need a CAN interface.  `tests/socketcan.sh` runs those `cansocket`
paths on two virtual interfaces, vcan0 and vcan1, in a user network
namespace (`unshare -rnm`), which needs no privilege on a kernel that
allows unprivileged user namespaces and has the vcan module.

`tests/board_probe.nv` runs `CanBoard` on a board that serves `hal.can`:
`novo build --target=frdm-mcxn947 tests/board_probe.nv` builds it, and
it reports each check over RTT in loopback, normal mode and bus-off.
The FRDM-MCXN947's suite in the novo-lang repository,
`orbit/bsp/nxp/mcxn9/frdm-mcxn947/tests/can.sh`, runs the same checks
against the registry's copy of this package and measures the line
coverage of `src/canboard.nv` on the board.

The references are ISO 11898-1 for the protocol, ISO 15765-2 for the
segmented transport, RM0090 (STM32F4, chapter 32) for bxCAN, RM0468
(STM32H723, chapter 56) for FDCAN, [embedded-can](https://docs.rs/embedded-can)
for the peripheral trait, and [SocketCAN](https://docs.kernel.org/networking/can.html)
for the kernel's frame and filter layouts. `tests/embedded_probe.nv` is a
firmware image that checks the frames, filters and ISO-TP at the embedded
tier and prints one line. `tests/driver_probe.nv` brings both drivers up
and is built for the STM32F407G-DISC1 and the NUCLEO-H723ZG; the drivers'
clock and pin routines write a board's registers, and the programs under
`examples/embedded/can_demo` run them on the boards.


## Licence

Apache-2.0. See `LICENSE`.

<!-- docs/writing-a-readme.md is the style guide for this page. -->
