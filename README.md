FPGA CAN Interface

#remark this is only working with oss-cad-suite 20251214 timming fails with latest version :-(

rx_frame_fsm.v is updatet so it now run on more oss-cad-suites builds.
crc15.v is optimized.

A bit-accurate, from-scratch CAN 2.0A controller implemented in Verilog for
Lattice iCE40 FPGAs (Alchitry Cu and compatible boards).

Verified interoperable with a Raspberry Pi Pico running
can2040 by
Kevin O'Connor at 125 kbit/s, 250 kbit/s,
500 kbit/s, and 1 Mbit/s — including CRC, bit-stuffing, ACK injection, EOF,
and back-to-back frame handling. Cross-validated with PulseView / sigrok's
independent CAN decoder: zero frame warnings over hundreds of thousands
of frames.

@125 kbit/s, 10 ms interval:  TX=580460 RX=580460 bad=0
@1 Mbit/s, TX=7222001 RX=7221966 bad=0

Highlights

    Pure RTL — no soft-CPU, no vendor IP

    Parametric bit-timing: TQ_PER_BIT and SAMPLE_TQ selectable per bitrate
    with compile-time sanity check (build fails if timing doesn't divide exactly)

    Bit-accurate ACK slot generation (delay-aligned to the ACK bit boundary)

    Bit-stuffing / de-stuffing matching CAN 2.0A exactly

    Hard-sync on every recessive→dominant edge

    IFS gating (bus_idle tracker requires 11 recessive bits before SOF)

    Self-loop safe: RX pipeline held in reset while TX engine drives the bus

    Dual-instance simulation testbench (two CAN nodes talking to each other)

    Compact footprint on iCE40-HX8K

Supported bit rates (exact timing)

With SYS_CLK_HZ = 100_000_000:
Bitrate	TQ_PER_BIT	SAMPLE_TQ	Sample point	Clock error
125 kbit/s	16	12	75 %	0.00 %
250 kbit/s	16	12	75 %	0.00 %
500 kbit/s	20	15	75 %	0.00 %
1 Mbit/s	10	8	80 %	0.00 %

The bit_timing.v module asserts at elaboration time that
SYS_CLK_HZ == CLKS_PER_TQ × BITRATE × TQ_PER_BIT — a non-exact combination
fails the build with a clear error message, preventing subtle runtime drift.
Repository layout

All Verilog sources are in the repo root.

.
├── main.v                   # Top-level (production: echo 0x123 → 0x124)
├── can_slave.v              # Full CAN node (RX + TX + ACK)
├── bit_timing.v             # Parametric TQ/bit, exact-divisor check
├── bus_idle.v               # Counts 11 recessive bits for "may TX"
├── rx_destuff.v             # Bit de-stuffing
├── rx_frame_fsm.v           # Frame parser (IDLE → SOF → ID → … → EOF)
├── crc15.v                  # CAN-15 CRC
├── ack_driver.v             # Bit-aligned dominant ACK pulse
├── tx_engine.v              # Shifts frame bits with stuffing
├── app_fsm.v                # App: receive LISTEN_ID, reply RESPONSE_ID
├── can_slave_dual_tb.v      # Two-instance Verilog testbench
├── run_dual_test.sh         # Run dual-simulation (Icarus Verilog)
│
├── can_pico_master.ino      # Pico master firmware (sends 0x123)
├── can_pico_slave.ino       # Pico echo-slave firmware (reference)
├── can2040.h                # can2040 header  (Kevin O'Connor, GPLv3)
├── can2040.c                # can2040 source  (Kevin O'Connor, GPLv3)
│
├── pins.pcf                 # iCE40 pin map
├── comp.sh                  # Synthesis and NextPNR Seed Sweep script
├── apio.ini                 # apio build configuration
├── comp.md                  # Flash procedure
├── LICENSE                  # MIT (see "Licenses & credits")
└── README.md

Hardware setup
Block	Purpose
iCE40-HX8K (Alchitry Cu)	Runs the CAN controller
100 MHz clock	System clock (SYS_CLK_HZ parameter)
TJA1050 / MCP2551	CAN transceiver
2× 120 Ω	CAN bus termination (both ends)
Raspberry Pi Pico	Partner node running can2040 firmware
Pin mapping (default main.v)
Signal	Direction	Notes
clk	in	100 MHz system clock
rst_n	in	Active-low reset
can_rx	in	From CAN transceiver RX
can_tx	out	To CAN transceiver TX
led[7:0]	out	Debug: rx/tx latch, heartbeat, count
Selecting bit rate

Change the can_slave instantiation in main.v:
Verilog

can_slave #(
    .SYS_CLK_HZ(100_000_000),
    .BITRATE(1_000_000),
    .TQ_PER_BIT(10),
    .SAMPLE_TQ(8)
) u_slave ( ... );

Remember to set the Pico to the same rate:
C

can2040_start(&g_can, sys_hz, 1000000, 20, 21);

Application layer (app_fsm)

The default application listens for CAN ID 0x123 and responds with
0x124 containing the same first two payload bytes:

Master (Pico)                    FPGA slave
──────────────                   ──────────
0x123 [counter_lo, counter_hi] ──▶
                               ◀── 0x124 [counter_lo, counter_hi]

This round-trip pattern is what the included Pico firmware exercises.
Pico reference firmware

Two Arduino sketches for Raspberry Pi Pico (RP2040 / RP2350) using
can2040 by
Kevin O'Connor.
can_pico_master.ino

Sends 0x123 on a configurable interval with an incrementing 16-bit counter;
counts replies of 0x124. Wiring: GPIO20 = RX, GPIO21 = TX, to a CAN
transceiver.

TX=14001 RX=14000 bad=0       (@ 1 Mbit/s, 1 ms interval)

can_pico_slave.ino

A software echo node. Useful for:

    Validating the Pico side alone (Pico-to-Pico) before involving the FPGA

    Providing a known-good reference for logic-analyser captures

    Regression testing the master sketch

Both sketches include can2040.h and can2040.c directly in the sketch folder
(Arduino IDE auto-compiles them). The can2040 files are distributed under
GPLv3 — see the header in can2040.c.

For upstream updates of the Pico CAN library, see:
https://github.com/KevinOConnor/can2040
Optimizing Place & Route: The comp.sh Seed Sweep Script

When compiling complex RTL designs that operate at high frequencies (like the 100 MHz target required for precise 1 Mbit/s CAN timing), the routing tool (nextpnr) can sometimes fail to meet timing constraints. Because routing algorithms rely on randomized initial states, the outcome heavily depends on the starting "seed."

To solve this, the repository includes comp.sh, an automated Bash script that utilizes the oss-cad-suite toolchain. Instead of failing on a single bad route, the script:

    Synthesizes the design using Yosys.

    Brute-forces the Place & Route process across a specified number of seeds (default: 512).

    Evaluates the maximum clock frequency achieved for each routing attempt.

    Identifies the "Winning Seed" with the highest maximum frequency.

    Automatically packs the winning configuration into a .bin file, flashes the FPGA, and deletes all temporary .asc files to save disk space.

Seed Sweep Performance Statistics

Based on a reference sweep of 512 seeds on the iCE40-HX8K running this exact CAN controller logic:

    Total Runs: 512

    Failed to meet 100 MHz constraint: 39 runs (~7.6%)

    Successfully met 100 MHz constraint: 473 runs (~92.4%)

    Comfortable Margin ( > 105 MHz ): 216 runs (~42.1%)

    Outstanding Margin ( > 110 MHz ): 45 runs (~8.8%)

    Absolute Winner (Seed 166): 118.93 MHz

These statistics demonstrate that while the default seed may occasionally fail, running a sweep guarantees a highly optimized, timing-stable bitstream with significant thermal and voltage headroom.

How to run the sweep:
Bash

./comp.sh

A log of all frequencies will be saved to seed_results.txt.
Simulation

A dual-instance testbench connects two can_slave instances on a shared
virtual bus. Both nodes send and receive, exercising ACK, IFS, arbitration.
Bash

./run_dual_test.sh

Expected:

Node A saw 0x125: 1  (self-loopback, >= 1 expected)
Node A saw 0x126: 1  data[15:0]=0xbeef  (from B, expect BEEF)
Node B saw 0x125: 1  data[15:0]=0xbeef  (from A, expect BEEF)
Node B saw 0x126: 1  (self-loopback, >= 1 expected)
=== PASS ===

Validation checklist
Test	Status
Dual-FPGA simulation (Icarus Verilog)	✅
FPGA ACK accepted by can2040 master	✅
FPGA 0x124 frame decoded by can2040	✅
PulseView CAN decoder, 0 warnings	✅
@ 125 kbit/s: 580 460+ frames, bad=0	✅
@ 250 kbit/s: clean round-trip	✅
@ 500 kbit/s: clean round-trip	✅
@ 1 Mbit/s, 1 ms interval, 14 000+ frames	✅

Tested against a Raspberry Pi Pico running can2040 with a TJA1050 transceiver
at all four supported bitrates.
Logic-analyser verification

Reproducing the scope captures:

    D0 = CAN bus line (transceiver RX or Pico TX pin)

    D1 = Pico's can_tx pin (so you can see who is driving)

    PulseView → add the Controller Area Network (CAN) decoder on D0

    Match bit rate and sample point to what is configured

You should see Start of frame, Identifier: 291 (0x123) / 292 (0x124),
DLC: 2, Data byte 0/1, CRC-15 sequence, ACK slot, End of frame —
with no warnings highlighted.
Licenses & credits

This repository contains code under two different licenses. Please respect
both when reusing or redistributing.
GPLv3 — Kevin O'Connor's can2040

The following two files are unmodified copies from the
can2040 project:

    can2040.c

    can2040.h

Software CANbus implementation for rp2040/rp2350
Copyright (C) 2022-2026  Kevin O'Connor <kevin@koconnor.net>
This file may be distributed under the terms of the GNU GPLv3 license.

Upstream repository: https://github.com/KevinOConnor/can2040

Full license text:   https://www.gnu.org/licenses/gpl-3.0.html

These files are included only as the reference-master firmware for the
Raspberry Pi Pico. They are not compiled into the FPGA bitstream and do
not form part of the Verilog build. The GPLv3 applies to them alone.
MIT — everything else in this repository

All Verilog source files (*.v), the Arduino sketches written for this
project (can_pico_master.ino, can_pico_slave.ino), build scripts,
testbenches, and documentation are distributed under the MIT license
(see LICENSE).
Why this split works

The Arduino sketches #include "can2040.h" and are linked with can2040.c
on the Pico side. The resulting Pico binary is a combined work and must
therefore be distributed under GPLv3 if you redistribute it. That is the
normal GPL behaviour and is fine — the Pico firmware is a development and
test tool, not the product.

The FPGA bitstream never touches these GPLv3 files. It is compiled from
Verilog only and remains MIT-licensed. You can use the FPGA CAN controller
in proprietary / closed-source designs without restriction.

Big thanks to Kevin O'Connor for can2040, which made this project practical
to verify: having a fully-functional software CAN partner on a Pico was
essential for cross-validating the FPGA implementation bit-for-bit.
Roadmap

    Error frames / error passive state handling

    Extended identifiers (29-bit, CAN 2.0B)

    CAN-FD support

    Wishbone / AXI-Lite wrapper for SoC integration

    Multi-master arbitration tests on a 3-node bus
