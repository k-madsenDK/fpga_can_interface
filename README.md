# FPGA CAN Interface

A bit-accurate, from-scratch **CAN 2.0A controller** implemented in Verilog for
Lattice iCE40 FPGAs (Alchitry Cu and compatible boards).

Verified interoperable with a Raspberry Pi Pico running
[can2040](https://github.com/KevinOConnor/can2040) by Kevin O'Connor at
**125 kbit/s** — including CRC, bit-stuffing, ACK injection, EOF, and
back-to-back frame handling. Cross-validated with PulseView / sigrok's
independent CAN decoder: zero frame warnings over thousands of frames.

```
TX=2791 RX=2790 bad=0        <- sustained error-free operation
```

---

## Highlights

- Pure RTL — no soft-CPU, no vendor IP
- Bit-accurate ACK slot generation (delay-aligned to the ACK bit boundary)
- Bit-stuffing / de-stuffing matching CAN 2.0A exactly
- Hard-sync on every recessive→dominant edge
- IFS gating (`bus_idle` tracker requires 11 recessive bits before SOF)
- Self-loop safe: RX pipeline held in reset while TX engine drives the bus
- Dual-instance simulation testbench (two CAN nodes talking to each other)
- Compact footprint on iCE40

---

## Repository layout

All Verilog sources are in the repo root.

```
.
├── main.v                   # Top-level (production: echo 0x123 → 0x124)
├── can_slave.v              # Full CAN node (RX + TX + ACK)
├── bit_timing.v             # 16-TQ/bit, 75% sample point, hard-sync
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
├── can_pico_slave.ino       # Pico echo-slave firmware (reference / Pico-to-Pico)
├── can2040.h                # can2040 header  (Kevin O'Connor, GPLv3)
├── can2040.c                # can2040 source  (Kevin O'Connor, GPLv3)
│
├── pins.pcf                 # iCE40 pin map
├── apio.ini                 # apio build configuration
├── comp.md                  # Flash procedure
└── README.md
```

---

## Hardware setup

| Block                 | Purpose                                   |
|-----------------------|-------------------------------------------|
| iCE40-HX8K (Alchitry Cu) | Runs the CAN controller                |
| 100 MHz clock         | System clock (`SYS_CLK_HZ` parameter)     |
| TJA1050 / MCP2551     | CAN transceiver                           |
| 2× 120 Ω              | CAN bus termination (both ends)           |
| Raspberry Pi Pico     | Partner node running can2040 firmware     |

### Pin mapping (default `main.v`)

| Signal    | Direction | Notes                                 |
|-----------|-----------|---------------------------------------|
| `clk`     | in        | 100 MHz system clock                  |
| `rst_n`   | in        | Active-low reset                      |
| `can_rx`  | in        | From CAN transceiver RX               |
| `can_tx`  | out       | To CAN transceiver TX                 |
| `led[7:0]`| out       | Debug: rx/tx latch, heartbeat, count  |

Bit rate is 125 kbit/s by default. Change `.BITRATE(125_000)` in `main.v` for
other rates.

---

## Application layer (`app_fsm`)

The default application listens for CAN ID `0x123` and responds with
`0x124` containing the same first two payload bytes:

```
Master (Pico)                    FPGA slave
──────────────                   ──────────
0x123 [counter_lo, counter_hi] ──▶
                               ◀── 0x124 [counter_lo, counter_hi]
```

This round-trip pattern is what the included Pico firmware exercises.

---

## Pico reference firmware

Two Arduino sketches for Raspberry Pi Pico (RP2040 / RP2350) using
[**can2040**](https://github.com/KevinOConnor/can2040) by
[Kevin O'Connor](https://github.com/KevinOConnor).

### `can_pico_master.ino`

Sends `0x123` every 10 ms with an incrementing 16-bit counter; counts replies
of `0x124`. Wiring: GPIO20 = RX, GPIO21 = TX, to a CAN transceiver.

```
TX=1234 RX=1233 bad=0
```

### `can_pico_slave.ino`

A software echo node. Useful for:
- Validating the Pico side alone (Pico-to-Pico) before involving the FPGA
- Providing a known-good reference for logic-analyser captures
- Regression testing the master sketch

Both sketches include `can2040.h` and `can2040.c` directly in the sketch folder
(Arduino IDE auto-compiles them). The can2040 files are distributed under
**GPLv3** — see the header in `can2040.c`.

For upstream updates of the Pico CAN library, see:
<https://github.com/KevinOConnor/can2040>

---

## Build & flash (FPGA)

Uses [apio](https://github.com/FPGAwars/apio) / yosys / nextpnr / icepack.

```bash
apio build        # synthesise + place & route
apio upload       # flash via programmer
```

---

## Simulation

A dual-instance testbench connects two `can_slave` instances on a shared
virtual bus. Both nodes send and receive, exercising ACK, IFS, arbitration.

```bash
./run_dual_test.sh
```

Expected:
```
Node A saw 0x125: 1  (self-loopback, >= 1 expected)
Node A saw 0x126: 1  data[15:0]=0xbeef  (from B, expect BEEF)
Node B saw 0x125: 1  data[15:0]=0xbeef  (from A, expect BEEF)
Node B saw 0x126: 1  (self-loopback, >= 1 expected)
=== PASS ===
```

---

## Validation checklist

| Test                                  | Status |
|---------------------------------------|:------:|
| Dual-FPGA simulation (Icarus Verilog) | ✅      |
| FPGA ACK accepted by can2040 master   | ✅      |
| FPGA 0x124 frame decoded by can2040   | ✅      |
| PulseView CAN decoder, 0 warnings     | ✅      |
| 2790+ frames round-trip, `bad=0`      | ✅      |

Tested against a Raspberry Pi Pico running can2040 with a TJA1050 transceiver
at 125 kbit/s.

---

## Logic-analyser verification

Reproducing the scope captures:

- **D0** = CAN bus line (transceiver RX or Pico TX pin)
- **D1** = Pico's `can_tx` pin (so you can see who is driving)
- PulseView → add the **Controller Area Network (CAN)** decoder on D0
- Bit rate: 125000, sample point: 75 %

You should see `Start of frame`, `Identifier: 291 (0x123)` / `292 (0x124)`,
`DLC: 2`, `Data byte 0/1`, `CRC-15 sequence`, `ACK slot`, `End of frame`
— with no warnings highlighted.

---

## Licenses & credits

- **Verilog sources** (`*.v`) and Arduino sketches (`*.ino`): MIT license
  *(add a `LICENSE` file to make this explicit)*
- **`can2040.h` / `can2040.c`**: Copyright © 2022-2026
