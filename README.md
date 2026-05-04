# FPGA CAN Interface

A bit-accurate, from-scratch CAN 2.0A controller implemented in Verilog for
Lattice iCE40 FPGAs, including the Alchitry Cu and compatible boards.

> [!NOTE]
> This project is currently known to work reliably with `oss-cad-suite 20251214`.
> Newer versions may fail timing in some builds.
>
> `rx_frame_fsm.v` has been updated to work with more oss-cad-suite builds, and
> `crc15.v` has been optimized.

The design has been verified interoperable with a Raspberry Pi Pico running
[`can2040`](https://github.com/KevinOConnor/can2040) by Kevin O'Connor at:

- 125 kbit/s
- 250 kbit/s
- 500 kbit/s
- 1 Mbit/s

Validation includes CRC, bit-stuffing, ACK injection, EOF, and back-to-back
frame handling.

The implementation has also been cross-validated with PulseView / sigrok's
independent CAN decoder with zero frame warnings over hundreds of thousands of
frames.

Example long-run results:

```text
@125 kbit/s, 10 ms interval: TX=580460 RX=580460 bad=0
@1 Mbit/s:                   TX=7222001 RX=7221966 bad=0
```

---

## Highlights

- Pure RTL implementation
  - No soft CPU
  - No vendor IP

- Parametric bit timing
  - `TQ_PER_BIT` and `SAMPLE_TQ` selectable per bitrate
  - Compile-time sanity check
  - Build fails if timing does not divide exactly

- Bit-accurate ACK slot generation
  - Delay-aligned to the ACK bit boundary

- CAN 2.0A compatible bit-stuffing and de-stuffing

- Hard synchronization on every recessive-to-dominant edge

- IFS gating
  - Bus-idle tracker requires 11 recessive bits before SOF

- Self-loop safe
  - RX pipeline is held in reset while the TX engine drives the bus

- Dual-instance simulation testbench
  - Two CAN nodes communicating on the same virtual bus

- Compact footprint on iCE40-HX8K

---

## Supported Bit Rates

With:

```text
SYS_CLK_HZ = 100_000_000
```

| Bitrate    | TQ_PER_BIT | SAMPLE_TQ | Sample point | Clock error |
|-----------:|-----------:|----------:|-------------:|------------:|
| 125 kbit/s | 16         | 12        | 75%          | 0.00%       |
| 250 kbit/s | 16         | 12        | 75%          | 0.00%       |
| 500 kbit/s | 20         | 15        | 75%          | 0.00%       |
| 1 Mbit/s   | 10         | 8         | 80%          | 0.00%       |

The `bit_timing.v` module asserts at elaboration time that:

```text
SYS_CLK_HZ == CLKS_PER_TQ × BITRATE × TQ_PER_BIT
```

A non-exact combination fails the build with a clear error message. This
prevents subtle runtime drift caused by invalid timing parameters.

---

## Repository Layout

All Verilog sources are located in the repository root.

```text
.
├── main.v                   # Top-level design
├── can_slave.v              # Full CAN node: RX + TX + ACK
├── bit_timing.v             # Parametric TQ/bit timing and exact-divisor check
├── bus_idle.v               # Counts 11 recessive bits before TX is allowed
├── rx_destuff.v             # CAN bit de-stuffing
├── rx_frame_fsm.v           # Frame parser: IDLE → SOF → ID → ... → EOF
├── crc15.v                  # CAN-15 CRC
├── ack_driver.v             # Bit-aligned dominant ACK pulse
├── tx_engine.v              # Frame shifter with CAN bit-stuffing
├── app_fsm.v                # App layer: receive LISTEN_ID, reply RESPONSE_ID
├── can_slave_dual_tb.v      # Two-instance Verilog testbench
├── run_dual_test.sh         # Run dual simulation using Icarus Verilog
│
├── can_pico_master.ino      # Pico master firmware, sends CAN ID 0x123
├── can_pico_slave.ino       # Pico echo-slave firmware, reference node
├── can2040.h                # can2040 header by Kevin O'Connor, GPLv3
├── can2040.c                # can2040 source by Kevin O'Connor, GPLv3
│
├── pins.pcf                 # iCE40 pin map
├── comp.sh                  # Synthesis and nextpnr seed sweep script
├── apio.ini                 # apio build configuration
├── comp.md                  # Flash procedure
├── LICENSE                  # MIT license, see license notes below
└── README.md
```

---

## Hardware Setup

| Block                         | Purpose                         |
|------------------------------|---------------------------------|
| iCE40-HX8K / Alchitry Cu      | Runs the CAN controller         |
| 100 MHz clock                 | System clock, `SYS_CLK_HZ`      |
| TJA1050 / MCP2551             | CAN transceiver                 |
| 2 × 120 Ω                     | CAN bus termination, both ends  |
| Raspberry Pi Pico             | Partner node running can2040    |

---

## Pin Mapping

Default top-level signals in `main.v`:

| Signal   | Direction | Description                         |
|----------|-----------|-------------------------------------|
| `clk`    | Input     | 100 MHz system clock                |
| `rst_n`  | Input     | Active-low reset                    |
| `can_rx` | Input     | From CAN transceiver RX             |
| `can_tx` | Output    | To CAN transceiver TX               |
| `led[7:0]` | Output  | Debug: RX/TX latch, heartbeat, count |

---

## Selecting Bit Rate

Change the `can_slave` instantiation in `main.v`.

Example for 1 Mbit/s:

```verilog
can_slave #(
    .SYS_CLK_HZ(100_000_000),
    .BITRATE(1_000_000),
    .TQ_PER_BIT(10),
    .SAMPLE_TQ(8)
) u_slave (
    // ...
);
```

Remember to set the Raspberry Pi Pico to the same bitrate:

```c
can2040_start(&g_can, sys_hz, 1000000, 20, 21);
```

---

## Application Layer

The default application listens for CAN ID `0x123` and responds with CAN ID
`0x124`.

The response contains the same first two payload bytes as the received frame.

```text
Master / Pico                    FPGA slave
──────────────                   ──────────

0x123 [counter_lo, counter_hi] ──▶
                               ◀── 0x124 [counter_lo, counter_hi]
```

This round-trip pattern is what the included Pico firmware exercises.

---

## Pico Reference Firmware

Two Arduino sketches are included for Raspberry Pi Pico, RP2040 / RP2350,
using Kevin O'Connor's `can2040`.

### `can_pico_master.ino`

The master firmware sends CAN ID `0x123` at a configurable interval with an
incrementing 16-bit counter. It counts replies with CAN ID `0x124`.

Default wiring:

| Pico GPIO | Direction | Description              |
|----------:|-----------|--------------------------|
| GPIO20    | RX        | From CAN transceiver     |
| GPIO21    | TX        | To CAN transceiver       |

Example output at 1 Mbit/s with 1 ms interval:

```text
TX=14001 RX=14000 bad=0
```

### `can_pico_slave.ino`

The slave firmware is a software echo node.

It is useful for:

- Validating the Pico side alone before involving the FPGA
- Pico-to-Pico CAN testing
- Providing a known-good reference for logic-analyser captures
- Regression testing the master sketch

Both Arduino sketches include:

```text
can2040.h
can2040.c
```

directly in the sketch folder. The Arduino IDE auto-compiles them.

The `can2040` files are distributed under GPLv3. See the header in
`can2040.c`.

Upstream project:

<https://github.com/KevinOConnor/can2040>

---

## Optimizing Place and Route

### `comp.sh` Seed Sweep Script

When compiling complex RTL designs that operate at high frequencies, such as a
100 MHz target required for precise 1 Mbit/s CAN timing, `nextpnr` can
sometimes fail timing constraints.

Because the routing algorithm depends on randomized initial states, the result
can vary significantly depending on the selected seed.

To work around this, the repository includes `comp.sh`, an automated seed sweep
script for the oss-cad-suite toolchain.

The script:

1. Synthesizes the design using Yosys
2. Runs place and route across a configurable number of seeds
3. Evaluates the maximum clock frequency for each attempt
4. Finds the best seed
5. Packs the winning configuration into a `.bin` file
6. Flashes the FPGA
7. Deletes temporary `.asc` files to save disk space

### Seed Sweep Performance

Based on a reference sweep of 512 seeds on the iCE40-HX8K running this CAN
controller logic:

| Result category                         | Count | Percentage |
|----------------------------------------|------:|-----------:|
| Total runs                             | 512   | 100%       |
| Failed to meet 100 MHz constraint      | 39    | 7.6%       |
| Met 100 MHz constraint                 | 473   | 92.4%      |
| Comfortable margin, above 105 MHz      | 216   | 42.1%      |
| Outstanding margin, above 110 MHz      | 45    | 8.8%       |
| Best result, seed 166                  | 118.93 MHz | -    |

These results show that while the default seed may occasionally fail, a seed
sweep can usually find a timing-stable bitstream with useful thermal and
voltage headroom.

Run the sweep with:

```bash
./comp.sh
```

A log of all frequencies is saved to:

```text
seed_results.txt
```

---

## Simulation

A dual-instance testbench connects two `can_slave` instances on a shared
virtual CAN bus.

Both nodes send and receive frames, exercising:

- ACK handling
- IFS gating
- Arbitration-related bus behavior
- Back-to-back frame handling

Run the simulation with:

```bash
./run_dual_test.sh
```

Expected output:

```text
Node A saw 0x125: 1  (self-loopback, >= 1 expected)
Node A saw 0x126: 1  data[15:0]=0xbeef  (from B, expect BEEF)
Node B saw 0x125: 1  data[15:0]=0xbeef  (from A, expect BEEF)
Node B saw 0x126: 1  (self-loopback, >= 1 expected)
=== PASS ===
```

---

## Validation Checklist

| Test                                           | Status |
|------------------------------------------------|:------:|
| Dual-FPGA simulation using Icarus Verilog       | ✅     |
| FPGA ACK accepted by can2040 master             | ✅     |
| FPGA `0x124` frame decoded by can2040           | ✅     |
| PulseView CAN decoder, zero warnings            | ✅     |
| 125 kbit/s, 580,460+ frames, `bad=0`            | ✅     |
| 250 kbit/s clean round-trip                     | ✅     |
| 500 kbit/s clean round-trip                     | ✅     |
| 1 Mbit/s, 1 ms interval, 14,000+ frames         | ✅     |

The design has been tested against a Raspberry Pi Pico running `can2040` with a
TJA1050 CAN transceiver at all four supported bitrates.

---

## Logic-Analyser Verification

To reproduce the scope captures:

1. Connect `D0` to the CAN bus line, transceiver RX, or Pico TX pin
2. Connect `D1` to the Pico `can_tx` pin
3. Open PulseView
4. Add the Controller Area Network, CAN, decoder on `D0`
5. Match the bit rate and sample point to the configured FPGA/Pico settings

You should see:

- Start of frame
- Identifier `291`, `0x123`
- Identifier `292`, `0x124`
- DLC `2`
- Data byte 0
- Data byte 1
- CRC-15 sequence
- ACK slot
- End of frame

No warnings should be highlighted by the decoder.

---

## Licenses and Credits

This repository contains code under two different licenses. Please respect both
when reusing or redistributing the files.

---

### GPLv3 — Kevin O'Connor's `can2040`

The following two files are unmodified copies from the `can2040` project:

```text
can2040.c
can2040.h
```

`can2040` is a software CAN bus implementation for RP2040 / RP2350.

```text
Copyright (C) 2022-2026 Kevin O'Connor <kevin@koconnor.net>
```

These files may be distributed under the terms of the GNU GPLv3 license.

Upstream repository:

<https://github.com/KevinOConnor/can2040>

Full GPLv3 license text:

<https://www.gnu.org/licenses/gpl-3.0.html>

These files are included only as reference firmware for the Raspberry Pi Pico.
They are not compiled into the FPGA bitstream and do not form part of the
Verilog build.

The GPLv3 license applies to these files alone.

---

### MIT — Everything Else

The following files are distributed under the MIT license:

- All Verilog source files, `*.v`
- Arduino sketches written for this project:
  - `can_pico_master.ino`
  - `can_pico_slave.ino`
- Build scripts
- Testbenches
- Documentation

See `LICENSE` for details.

---

## Why the License Split Works

The Arduino sketches include `can2040.h` and are linked with `can2040.c` on the
Pico side.

The resulting Pico binary is therefore a combined work and must be distributed
under GPLv3 if redistributed. This is normal GPL behavior and is acceptable here
because the Pico firmware is a development and test tool, not the FPGA product.

The FPGA bitstream never uses the GPLv3 files. It is compiled from Verilog only
and remains MIT licensed.

This means the FPGA CAN controller can be used in proprietary or closed-source
designs without GPL restrictions.

Many thanks to Kevin O'Connor for `can2040`. Having a fully functional software
CAN partner on a Pico made it practical to verify this FPGA implementation
bit-for-bit.

---

## Roadmap

Planned or possible future improvements:

- Error frames and error-passive state handling
- Extended identifiers, CAN 2.0B, 29-bit IDs
- CAN-FD support
- Wishbone / AXI-Lite wrapper for SoC integration
- Multi-master arbitration tests on a three-node bus
