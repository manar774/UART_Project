# APB UART

A complete RTL implementation of a **UART (Universal Asynchronous Receiver/Transmitter)** with an **APB (Advanced Peripheral Bus) slave interface**, synthesized and verified on the **Basys3 FPGA (Artix-7)**.

---

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Module Descriptions](#module-descriptions)
  - [TX — UART Transmitter](#tx--uart-transmitter)
  - [RX — UART Receiver](#rx--uart-receiver)
  - [APB UART Wrapper](#apb-uart-wrapper)
- [Register Map](#register-map)
- [APB Interface](#apb-interface)
- [Simulation](#simulation)
- [FPGA Implementation](#fpga-implementation)

---

## Overview

The design implements a standard 8N1 UART (8 data bits, no parity, 1 stop bit) operating at **9600 baud** with a **100 MHz** system clock. The UART core is wrapped in an APB slave interface, allowing a processor or bus master to configure and control TX/RX through memory-mapped registers.

**Key features:**

- 8N1 UART protocol at 9600 baud (fixed)
- 5-state FSM for both TX and RX (IDLE → START → DATA → STOP → CLEAN_UP)
- Double-register synchronizer on the RX input for metastability protection
- Mid-bit sampling on RX for robust data recovery
- APB slave wrapper with 5 memory-mapped 32-bit registers
- Independent soft-reset for TX and RX via the control register
- Synthesized and tested on Digilent Basys3 (Xilinx Artix-7 XC7A35T)

---

## Project Structure

```
UART_Project-main/
├── src/
│   ├── TX.v              # UART Transmitter FSM
│   ├── RX.V              # UART Receiver FSM
│   └── apb_uart.v        # APB slave wrapper integrating TX and RX
│
├── dv/
│   ├── apb_uart_tb.sv    # Full APB-level testbench (TX + RX test)
│   ├── tx_tb.SV          # Standalone TX testbench
│   ├── rx_tb.sv          # Standalone RX testbench
│   ├── run.do            # ModelSim script for full APB testbench
│   ├── run_tx.do         # ModelSim script for TX testbench
│   └── run_rx.do         # ModelSim script for RX testbench
│
├── fpga/
│   ├── Constraints_basys3.xdc   # Vivado pin constraints for Basys3
│   └── utilization.rpt          # Vivado synthesis utilization report
│
└── docs/
    └── docs.pdf          # Full project documentation
```

---

## Module Descriptions

### TX — UART Transmitter

**File:** `src/TX.v`

A 5-state Moore FSM that serializes an 8-bit byte over the `tx` line.

```
IDLE → START → DATA → STOP → CLEAN_UP → IDLE
```

| State      | Action                                               |
|------------|------------------------------------------------------|
| `IDLE`     | `tx` held high; captures `data_in` when `tx_en=1`   |
| `START`    | Drives `tx` low for one full bit period              |
| `DATA`     | Shifts out 8 bits LSB-first, one per bit period      |
| `STOP`     | Drives `tx` high for one full bit period; sets `done`|
| `CLEAN_UP` | Clears `done` and `busy`; returns to IDLE            |

**Port list:**

| Port      | Dir    | Width | Description                         |
|-----------|--------|-------|-------------------------------------|
| `clk`     | input  | 1     | System clock (100 MHz)              |
| `rst`     | input  | 1     | Synchronous active-high reset       |
| `data_in` | input  | 8     | Byte to transmit                    |
| `tx_en`   | input  | 1     | Level-triggered start (managed by APB CTRL) |
| `done`    | output | 1     | High during STOP state              |
| `busy`    | output | 1     | High while transmission is in progress |
| `tx`      | output | 1     | Serial output line                  |

Bit period = `100_000_000 / 9600 ≈ 10417` clock cycles.

---

### RX — UART Receiver

**File:** `src/RX.V`

A 5-state Moore FSM that deserializes an incoming serial frame into an 8-bit byte.

```
IDLE → START → DATA → STOP → CLEAN_UP → IDLE
```

| State      | Action                                                       |
|------------|--------------------------------------------------------------|
| `IDLE`     | Monitors synchronized `rx` for a falling edge (start bit)   |
| `START`    | Waits half a bit period, re-checks `rx` is still low         |
| `DATA`     | Samples each bit at the center of its bit period             |
| `STOP`     | Asserts `rx_done`; waits one full bit period                 |
| `CLEAN_UP` | Holds `rx_done` for one extra bit period, then clears it     |

**Metastability protection:** The raw `rx` input passes through a two-stage synchronizer (`r_Rx_Data_R → r_Rx_Data`) before being used by the FSM.

**Mid-bit sampling:** In START state the FSM waits `HALF_CYCLES = COUNT_CYCLES / 2` before sampling the first data bit, centering all subsequent samples within their bit window.

**Port list:**

| Port      | Dir    | Width | Description                         |
|-----------|--------|-------|-------------------------------------|
| `clk`     | input  | 1     | System clock (100 MHz)              |
| `rst`     | input  | 1     | Synchronous active-high reset       |
| `rx`      | input  | 1     | Serial input line                   |
| `rx_en`   | input  | 1     | Enable receiver                     |
| `rx_data` | output | 8     | Received byte (valid when `rx_done`) |
| `rx_done` | output | 1     | High after a complete frame is received |
| `rx_busy` | output | 1     | High while reception is in progress |

---

### APB UART Wrapper

**File:** `src/apb_uart.v`

An **APB slave** wrapping the TX and RX cores. Implements the standard 3-phase APB protocol (IDLE → SETUP → ACCESS) with a single-cycle `PREADY` assertion in the ACCESS phase.

**APB signal mapping:**

| APB Signal | Direction | Description                     |
|------------|-----------|---------------------------------|
| `PCLK`     | input     | APB clock (100 MHz)             |
| `PRESETn`  | input     | Active-low asynchronous reset   |
| `PADDR`    | input     | 32-bit address                  |
| `PSEL`     | input     | Slave select                    |
| `PENABLE`  | input     | Enable (2nd cycle strobe)       |
| `PWRITE`   | input     | Write enable                    |
| `PWDATA`   | input     | 32-bit write data               |
| `PRDATA`   | output    | 32-bit read data                |
| `PREADY`   | output    | Transfer complete                |
| `rx`       | input     | UART RX serial line             |
| `tx`       | output    | UART TX serial line             |

`PRESETn` is inverted internally to an active-high `sys_rst` fed to both TX and RX cores. Independent soft-resets are derived from `ctrl_reg[2]` (TX) and `ctrl_reg[3]` (RX), OR'd with the system reset.

---

## Register Map

Base address: `0x00000000`

| Offset | Name       | Access | Description                                          |
|--------|------------|--------|------------------------------------------------------|
| `0x00` | `CTRL`     | R/W    | Control register                                     |
| `0x04` | `STATS`    | R      | Status register                                      |
| `0x08` | `TX_DATA`  | R/W    | TX data register (bits [7:0] used)                   |
| `0x0C` | `RX_DATA`  | R      | RX data register (bits [7:0] hold received byte)     |
| `0x10` | `BAUDIV`   | R/W    | Baud divisor (readable/writable; not used in hardware)|

### CTRL Register (`0x00`)

| Bit | Name       | Description                                      |
|-----|------------|--------------------------------------------------|
| 0   | `tx_en`    | Level-trigger TX start; write 1 to start, 0 to stop |
| 1   | `rx_en`    | Enable RX receiver                               |
| 2   | `tx_rst`   | Soft-reset TX (OR'd with system reset)           |
| 3   | `rx_rst`   | Soft-reset RX (OR'd with system reset)           |

### STATS Register (`0x04`) — Read Only

| Bit | Name       | Description                   |
|-----|------------|-------------------------------|
| 0   | `rx_busy`  | RX frame in progress          |
| 1   | `tx_busy`  | TX frame in progress          |
| 2   | `rx_done`  | RX frame complete             |
| 3   | `tx_done`  | TX frame complete             |

---

## Simulation

### Requirements

- ModelSim / QuestaSim
- SystemVerilog support (IEEE 1800)

### Full APB Testbench

```tcl
cd dv/
vsim -do run.do
```

The `apb_uart_tb.sv` testbench exercises the complete TX and RX path through the APB interface:

**TX test sequence:**
1. Apply hard reset via `PRESETn`
2. Soft-reset TX via `CTRL[2]`
3. Write `0xA5` to `TX_DATA`
4. Assert `tx_en` via `CTRL[0]`
5. Verify `tx_busy` is set in `STATS`
6. Check the start bit on `tx` (expected low after half a bit period)
7. Check all 8 data bits LSB-first, one per bit period
8. Check the stop bit (expected high)
9. Verify `tx_done` is set in `STATS`

**RX test sequence:**
1. Enable RX via `CTRL[1]`
2. Drive `rx` low (start bit), verify `rx_busy` in `STATS`
3. Drive 8 data bits LSB-first for `0xA5`
4. Drive `rx` high (stop bit), verify `rx_done` in `STATS`
5. Read `RX_DATA` and compare against expected `0xA5`
6. Soft-reset RX to clear `rx_done`, verify it is cleared

Both pass/fail counts are printed at the end of simulation.

### Standalone Testbenches

```tcl
cd dv/
vsim -do run_tx.do   # TX only
vsim -do run_rx.do   # RX only
```

---

## FPGA Implementation

**Target:** Digilent Basys3 — Xilinx Artix-7 XC7A35T-1CPG236  
**Tool:** Vivado 2018.2

### Pin Assignments (`Constraints_basys3.xdc`)

| Signal    | FPGA Pin | Standard   | Description              |
|-----------|----------|------------|--------------------------|
| `PCLK`    | W5       | LVCMOS33   | 100 MHz onboard oscillator |
| `PRESETn` | U18      | LVCMOS33   | Center push-button (active-low) |
| `tx`      | A18      | LVCMOS33   | USB-UART bridge TX (FPGA → PC) |
| `rx`      | B18      | LVCMOS33   | USB-UART bridge RX (PC → FPGA) |

### Synthesis Utilization Summary

| Resource         | Used | Available | Utilization |
|------------------|------|-----------|-------------|
| Slice LUTs       | 144  | 20,800    | 0.69%       |
| Slice Registers  | 199  | 41,600    | 0.48%       |
| Bonded IOBs      | —    | 106       | —           |
| BUFG             | 1    | 32        | 3.13%       |

The design is extremely lightweight, consuming less than 1% of the available logic resources on the Artix-7 XC7A35T.
