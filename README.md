# UART Transmitter & Receiver (Verilog)

Part of a personal Verilog → RISC-V learning roadmap: Verilog fundamentals → FSM design → UART TX/RX → PYNQ-Z2 deployment → RISC-V core bring-up.

## Status

- [x] UART TX (`rtl/TX.v`) — 2-block FSM, IDLE/START/DATA/STOP, configurable parity, self-checking testbench
- [x] UART RX (`rtl/RX.v`) — synchronizer + 2-block FSM, parity error and framing error detection
- [x] TX + RX loopback testbench — verifies correct byte round-trip across odd/even/none parity modes
- [ ] Baud rate divider (in progress) — will decouple the FSMs' bit timing from an arbitrary system clock frequency
- [ ] PYNQ-Z2 deployment (Vivado) — pending baud divider + full simulation sign-off

## Repository Structure

```
rtl/     - synthesizable design modules (TX.v, RX.v)
sim/     - testbenches (RX_TB.v, TX_TB_.v, tx_rx_loopback_TB.v)
```

## Module Parameters

Both `TX` and `RX` expose `clock_per_bit` as an overridable `parameter`, representing the number of clock cycles per UART bit period. In simulation this is set to a small value (e.g. 16) for readable waveforms; on real hardware this will be driven by a baud rate divider computing `system_clock_freq / (16 * baud_rate)`.

## Ports

### TX

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | input | 1 | System clock |
| `reset` | input | 1 | Synchronous reset |
| `tx_start` | input | 1 | One-cycle pulse; loads `data_in` and begins transmission |
| `parity_mode` | input | 2 | `00`=none, `01`=odd, `10`=even |
| `data_in` | input | 8 | Byte to transmit |
| `tx` | output | 1 | Serial output line (idles HIGH) |
| `busy` | output | 1 | HIGH from the cycle `tx_start` is accepted until STOP completes |

### RX

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | input | 1 | System clock |
| `rx` | input | 1 | Serial input line (expected idle HIGH) |
| `reset` | input | 1 | Synchronous reset |
| `parity_mode` | input | 2 | Must match the transmitting side |
| `busy` | output | 1 | HIGH while a frame is being received |
| `data_ready` | output | 1 | Single-cycle pulse when a byte has finished reception |
| `parity_error` | output | 1 | Single-cycle pulse if the received parity bit doesn't match the expected value |
| `framing_error` | output | 1 | Single-cycle pulse if the stop bit was sampled LOW instead of HIGH |
| `data_rx` | output | 8 | The received byte, valid from the cycle after `data_ready` pulses |

## Flags in Detail

All four RX status outputs (`busy`, `data_ready`, `parity_error`, `framing_error`) are driven by a **combinational** `always @(*)` block, not registered outputs. This has one critical consequence: `data_ready`, `parity_error`, and `framing_error` are only valid for a **single delta cycle**, at the exact moment `state == STOP` and `baud_counter == 0`. They are not held or latched.

This matters for anyone writing a testbench or downstream logic against this module:

- **Don't** check these flags on the next `@(posedge clk)` , by then the combinational block has already re-evaluated for the new state (`IDLE`) and cleared them back to 0.
- **Do** either watch them with an event-sensitive block (`always @(parity_error or framing_error)`) or register them yourself with a small sampler (`always @(posedge clk) flag_sample <= flag;`) if you need to hold the value past that single cycle.

### `data_ready`

Pulses once, in the same cycle RX transitions from `STOP` back to `IDLE`. `data_rx` is updated one cycle earlier (during the STOP-state sequential block, when `baud_counter` first hits 0), so by the time `data_ready` pulses, `data_rx` already holds the correct byte.

### `parity_error`

Pulses if `expected_parity != shift_reg[8]` at the moment STOP completes, and only when `parity_mode != PARITY_NONE`. `expected_parity` is recomputed live from `shift_reg[7:0]` using XOR (even) or XNOR (odd) — it does not distinguish `PARITY_NONE` itself; that's handled by the separate `parity_mode` check.

### `framing_error`

Pulses if `rx_synq` is sampled LOW at the exact instant `baud_counter` reaches 0 in STOP — i.e., the stop bit never returned HIGH as UART framing requires. Because this check happens at the very *end* of the STOP window (not the middle, unlike the start-bit check in START), any test stimulus meant to trigger this flag must remain LOW for the entire STOP duration, not just a nominal bit period. See `sim/rx_TB.v` for the `#180` corrupted stop-bit stimulus and why that specific value was needed.

### `busy`

HIGH for the entire duration of a frame (from IDLE detecting a start condition through the end of STOP), LOW only in true IDLE. Used by testbenches to know when it's safe to start the next frame without triggering a false start.

## Running the Testbenches

Example with Icarus Verilog:

```bash
iverilog -o sim_out rtl/TX.v rtl/RX.v sim/tx_rx_loopback_TB.v
vvp sim_out
gtkwave loopback_waves.vcd
```

## Design Notes

- Both modules use the standard two-block FSM style (clocked state register + combinational next-state/output logic).
- RX includes a 2-stage synchronizer (`rx_unsync` → `rx_synq`) on the asynchronous `rx` input to avoid metastability. This introduces a fixed 2-cycle latency that several internal timing calculations (e.g. the IDLE→START handoff) explicitly compensate for.
- Parity modes: `00` = none, `01` = odd, `10` = even (must match between TX and RX for correct operation).
- RX's STOP state intentionally reloads `baud_counter` to `clock_per_bit >> 1` (half a bit period) rather than a full period, allowing RX to re-arm and detect the next start bit sooner. This was a deliberate design choice made during RX's development, but it means stimulus that needs to still be "wrong" when STOP samples it must account for this half-period window, not a full bit period.

## Known Fragile Points

- The `#180` corrupted stop-bit duration in `rx_TB.v` is not derived from a formula — it was tuned empirically to reliably outlast STOP's sampling window. If `clock_per_bit` changes, this value will need to be recalculated.
