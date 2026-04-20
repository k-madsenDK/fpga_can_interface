#!/usr/bin/env bash
set -e

# Brug oss-cad-suite i ~/Documents/oss-cad-suite
OSS_BIN="$HOME/Documents/oss-cad-suite/bin"

YOSYS="$OSS_BIN/yosys"
NEXTPNR="$OSS_BIN/nextpnr-ice40"
ICEPACK="$OSS_BIN/icepack"
ICEPROG="$OSS_BIN/iceprog"

# Tjek at værktøjerne findes
for tool in "$YOSYS" "$NEXTPNR" "$ICEPACK" "$ICEPROG"; do
    if [ ! -x "$tool" ]; then
        echo "FEJL: Kan ikke finde $tool"
        exit 1
    fi
done

TOP=main

SRC="main.v \
     can_slave.v \
     app_fsm.v \
     bit_timing.v \
     bus_idle.v \
     rx_destuff.v \
     crc15.v \
     rx_frame_fsm.v \
     ack_driver.v \
     tx_engine.v"
     
PCF="pins.pcf"

echo "=== Syntese med Yosys ==="
"$YOSYS" -p "read_verilog $SRC; synth_ice40 -top $TOP -json $TOP.json"

echo "=== Place & route med nextpnr-ice40 (HX8K-CB132) ==="
"$NEXTPNR" --hx8k --package cb132 \
  --json "$TOP.json" \
  --pcf "$PCF" \
  --asc "$TOP.asc" \
  --freq 100

echo "=== Genererer bitfil med icepack ==="
"$ICEPACK" "$TOP.asc" "$TOP.bin"

echo "=== Programmerer FLASH med iceprog ==="
"$ICEPROG" "$TOP.bin"

echo "Færdig."
