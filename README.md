# Systolic-Array-Based AI/ML Accelerator 

## 1. Overview 
This repository contains the RTL-GDS of a AI/ML Accelerator, AI/ML accelerators are used because they are specifically engineered to handle the unique, high-intensity mathematical demands 
of artificial intelligence workloads far more efficiently than general-purpose processors (like CPUs). 

The architecture features an AXI4-Lite Slave interface dedicated to configuring the accelerator parameters (such as base address, matrix size, and quantization mode) and monitoring 
execution status. To drive the core computation, the design incorporates a centralized Array Controller FSM responsible for orchestrating the precise sequence of weight fetching, 
systolic execution, and result draining. To maximize throughput and efficiency, the datapath utilizes a 4x4 Systolic Processing Element (PE) Array that ensures highly parallel 
Multiply-Accumulate (MAC) operations through spatial data reuse. Additionally, a 4KB Dual-Port SRAM is integrated directly into the datapath to buffer weights and activations locally, 
feeding the systolic pipeline continuously and preventing computational stalls caused by external memory latency.

## 2. Project Objectives

- **End-to-End Silicon Implementation**: To design, verify, and physically implement a complex AI/ML hardware accelerator, driving the design from behavioral RTL down to a routable 
GDSII layout using the OpenLane EDA flow.

- **Scalable Compute Architecture**: To architect a 4x4 systolic array capable of performing highly parallel, variable-precision (8-bit and 4-bit) Multiply-Accumulate (MAC) 
operations for efficient neural network inference.

- **Industry-Standard SoC Integration**: To ensure the IP is ready for seamless integration into modern System-on-Chip (SoC) environments by designing a compliant AXI4-Lite slave interface and 
an integrated dual-port SRAM for local data buffering.

- **PPA Optimization and Signoff**: To target the SkyWater 130nm (Sky130A) technology node and successfully achieve a clean physical design signoff (Zero DRC/LVS violations) while meeting strict Power, Performance, and Area constraints.

## 3. Key Objectives 

- **4x4 Systolic Processing Array**: Executes highly parallel Multiply-Accumulate (MAC) operations with spatial data reuse, maximizing computational throughput for neural network matrix multiplications

- **Configurable Quantization Modes**: Supports dynamic switching between 8-bit and 4-bit integer precision, allowing software to double the computation throughput when lower dynamic range is sufficient.

- **Integrated Dual-Port SRAM**: Internal 4KB (512 x 64-bit) memory block decouples the systolic array from external bus latency, providing continuous, high-bandwidth streaming of weights and activations.

- **Hardware State Machine Orchestration**: A centralized Array Controller FSM independently manages weight fetching, systolic execution, and result draining, minimizing host CPU overhead.

- **Standard AMBA AXI4-Lite Protocol**: Features a compliant memory-mapped slave interface dedicated to configuring computation parameters (base address, matrix size) and polling execution status.

## 4. System Architecture 
The AI/ML Accelerator is highly modular, strictly separating the control plane (bus interfacing and state management) from the datapath (computation and memory). It uses a top-level wrapper, [accel_ip_top](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/accel_ip_top.v), to integrate five core sub-modules.

### A. The Core Math Unit: [processing_element](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/processing_element.v)                  [img](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/Images/processing_element.png)
The smallest, most critical building block of the datapath. Each PE is responsible for a single Multiply-Accumulate (MAC) operation.

- **2-Stage Pipelining**: To achieve a high clock frequency (66.67 MHz on a 130nm node), the PE splits the workload. Stage 1 captures inputs; Stage 2 performs the combinational multiplication and accumulation.

- **Dynamic Precision Mode**: The multiplier physically adapts based on the pe_mode signal. It can execute standard 8-bit math, or switch to 4-bit operations to support aggressively quantized neural networks.

- **Saturation Logic**: It utilizes a 20-bit internal accumulator for an 8-bit multiply. If the sum exceeds the maximum 20-bit value (_(0xFFFFF)_), the hardware features a saturation clamp. Instead of wrapping around to zero (which would catastrophically invert a neural network's prediction), it locks the value at the maximum maximum limit and asserts an overflow flag.

### B. The Compute Fabric: [pe_array_4x4](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/pe_array_4x4.v)                  [img](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/Images/pe_array_4x4_transcript.png)

This module defines the systolic grid architecture. It instantiates 16 Processing Elements and wires them in a 2D mesh.

- **Spatial Data Reuse**: Instead of fetching data from memory for every single math operation, activations flow horizontally from left to right, and weights flow vertically from top to bottom. A piece of data fetched once is reused across multiple PEs in the same row or column.

- **Sequential Streaming**: To minimize routing congestion in the physical layout (GDSII), the array does not output a massive 256-bit bus at once. Instead, it streams the final 16-bit results out one column per cycle, dramatically reducing routing complexity and required wire tracks.
    
### C. Execution Orchestrator: [array_controller_fsm](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/array_controller_fsm.v)                  [img](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/Images/array_controller_fsm_transcript.png)
This is the "brain" of the accelerator. Once the CPU sends the START command, this hardware state machine takes complete control, freeing the CPU to do other tasks.

- **State Progression**: It automatically drives the hardware through a strict pipeline: (_IDLE_) → (_LOAD_WEIGHTS_) (fetching weights from (_SRAM_)) → (_COMPUTE_) (firing the PE array) → (_DRAIN_) (flushing the pipeline) → (_DONE_STATE_) (writing results back to memory).

- **Dynamic Masking**: Based on the user's matrix_size configuration, the FSM dynamically toggles the enable pins (_(pe_en)_) for specific rows in the array. This ensures power is not wasted computing unused rows.

- **Watchdog & Error Tracking**: It features an internal 8-bit watchdog counter. If the computation stalls and exceeds 50 cycles, or if any PE reports an accumulator overflow, the FSM safely aborts the operation, moves to an (_ERROR_STATE_), and logs a distinct hardware error code for the CPU to read.

### D. Local Memory Buffer: [sram_controller](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/sram_controller.v)                  [img](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/Images/sram_controller_transcript.png)

This is a 4KB (512 locations × 64-bit) dual-port memory wrapper that feeds the computational datapath.

- **Latency Abstraction**: Reading from external main memory (DRAM) is slow and unpredictable. This internal SRAM provides a guaranteed 2-cycle read latency.

- **Pipeline Synchronization**: It includes an internal busy-flag state machine that tracks the 2-cycle read delay, generating a (_sram_valid_) strobe exactly when the data is ready to be latched by the FSM or PE array, preventing data misalignment.

### E. Configuration Interface: [axi4_lite_slave](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/axi4_lite_slave.v)                  [img](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/Images/axi-4_lite_transcript.png)

This module acts as the bridge between the host CPU and the accelerator hardware.
This is the entry point for the system. Before any matrix multiplication occurs, the CPU must define the base memory address, the active matrix size, and the quantization mode. The AXI Slave receives this over the AXI4-Lite bus and safely registers it for the FSM to use.

- **Address Decoding**: It decodes specific 32-bit AXI addresses to route data to the correct registers (e.g., (_0x0000_) for Command, (_0x0004_) for Base Address, (_0x0008_) for Matrix Size).

- **Protocol Protection (SLVERR)**: It enforces hardware security by strictly delineating Read-Only and Write-Only memory spaces. If the CPU maliciously or accidentally attempts to write to the Read-Only Status register ((_0x0010_)), the module immediately traps the request and issues a Slave Error (SLVERR) response.

- **Command Handshakes**: Writing a (_0x01 (START)_) to the Control register initiates the hardware. The module also exposes real-time flags (_(DONE, BUSY, ERROR, OVERFLOW)_) back to the CPU for polling.

### F. Top-Level Integration: [accel_ip_top](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/accel_ip_top.v)                  [img](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/Images/accel_top_transcript.png)

This is the physical and logical wrapper of the IP. It acts as the central hub, mapping external SoC signals to the internal sub-systems.

- **Signal Routing**: It directly wires the configuration outputs from the AXI4-Lite Slave into the FSM, and routes the memory/compute signals between the FSM, the SRAM, and the PE Array.

- **Data Unpacking**: It handles the continuous 64-bit data streams coming from the SRAM and unpacks them into discrete 8-bit activation and weight buses to feed the systolic rows.

## 5. Memory-Mapped Register (MAR) Map

The IP is controlled via a set of 32-bit memory-mapped registers accessible over the AXI4-Lite bus.

| Offset   | Register         | Access | Bit(s)  | Field          | Description |
|----------|------------------|--------|----------|----------------|-------------|
| `0x0000` | **CTRL**         | W      | [2]      | `CLEAR`        | Async clear for PE accumulators and FSM status. |
|          |                  |        | [1]      | `STOP`         | Immediately halts FSM and safely drains pipeline. |
|          |                  |        | [0]      | `START`        | Initiates the computation sequence. |
| `0x0004` | **BASE_ADDR**    | W      | [15:0]   | `base_addr`    | 16-bit base address pointing to SRAM data start. |
| `0x0008` | **MATRIX_SIZE**  | W      | [1:0]    | `matrix_size`  | Active row configuration (`00`: 1x4, `01`: 2x4, `10`: 3x4, `11`: 4x4). |
| `0x000C` | **MODE**         | W      | [1:0]    | `quantization` | Precision mode (`00`: 8-bit MAC, `01`: 4-bit MAC). |
| `0x0010` | **STATUS**       | R      | [3]      | `OVERFLOW`     | Latched high if any PE accumulator saturated. |
|          |                  |        | [2]      | `ERROR`        | High if watchdog timeout or critical hardware fault. |
|          |                  |        | [1]      | `BUSY`         | High while FSM is active. |
|          |                  |        | [0]      | `DONE`         | High when computation completes and results are stored. |
| `0x0014` | **CYCLE_COUNT**  | R      | [31:0]   | `cycle_count`  | Hardware cycle counter for performance profiling. |
| `0x0018` | **ERROR_CODE**   | R      | [31:0]   | `error_code`   | Lower 4-bits: PE row overflow mask. `0xDEAD0001`: Watchdog timeout. |

## 6. Physical Design (PPA Metrics)

The IP was synthesized, placed, and routed using the OpenLane flow, achieving a clean LVS and DRC signoff.

| Metric                  | Value |
|--------------------------|-------|
| **Technology Node**      | SkyWater 130nm (Sky130A) |
| **Clock Frequency**      | 66.67 MHz (15ns Period) |
| **Core Area**            | 2.31 mm² |
| **Final Utilization**    | 35.74% |
| **Standard Cell Count**  | 38,097 |
| **Total Wire Length**    | 4,680,124 µm |
| **LVS / DRC**            | 0 Violations (Clean Signoff) |


## 7. Execution Guide: RTL-to-GDSII Flow

This section details the physical implementation pipeline using the OpenLane EDA framework. You can reproduce the final layout using either the automated push-button flow or the interactive stage-by-stage flow.

---

### A. Environment Setup

Ensure your local environment is configured with the necessary tools and design kits before initiating the flow.

#### Requirements

- **Operating System:** Ubuntu 22.04 (Recommended)
- **Dependencies:** Docker, OpenLane, SkyWater 130nm PDK (Sky130A)

#### Launch OpenLane Container

```bash
cd /path/to/openlane
make mount
```

---

### B. Automated Flow (Push-Button)

Use this method for rapid, hands-off generation of the GDSII layout utilizing the predefined parameters in `config.tcl`.

#### Run Flow

```bash
./flow.tcl -design accel_ip
```

#### Output Location

Upon successful completion, the final physical layout will be generated at:

```text
designs/accel_ip/runs/RUN_<timestamp>/results/signoff/accel_ip_top.gds
```

---

### C. Interactive Flow (Stage-by-Stage)

Use this method for debugging, analyzing intermediate metrics, or fine-tuning individual stages of the physical design flow.

#### Initialize Interactive Mode

```bash
./flow.tcl -interactive
```

#### Load OpenLane Environment

```tcl
package require openlane 0.9
prep -design accel_ip
```

#### Logic Synthesis

Maps behavioral RTL into technology-mapped standard cells using **Yosys** and **ABC**.

```tcl
run_synthesis
```

#### Floorplanning & Power Distribution Network (PDN)

Defines the core area, I/O placement, and generates the power delivery network using **OpenROAD**.

```tcl
run_floorplan
run_pdn
```

#### Placement

Performs global and detailed placement using **RePlace** and **OpenDP**.

```tcl
run_placement
```

#### Clock Tree Synthesis (CTS)

Builds the clock distribution network and minimizes clock skew using **TritonCTS**.

```tcl
run_cts
```

#### Routing

Performs global and detailed routing using **FastRoute** and **TritonRoute**.

```tcl
run_routing
```

#### Parasitic Extraction & Static Timing Analysis

Extracts RC parasitics and verifies timing closure using **OpenRCX** and **OpenSTA**.

```tcl
run_parasitics
run_sta
```

#### Physical Verification & Signoff

Runs final verification checks including:

- Design Rule Check (DRC)
- Layout Versus Schematic (LVS)
- Antenna Rule Checks

```tcl
run_magic
run_magic_drc
run_lvs
run_antenna_check
```

---

### D. Layout Verification

To visually inspect the final routed GDSII layout or debug DRC violations, open the design in **Magic VLSI**.

### Open GDSII in Magic

```bash
magic -T /path/to/sky130A/libs.tech/magic/sky130A.tech \
      designs/accel_ip/runs/RUN_<timestamp>/results/signoff/accel_ip_top.gds
```

---

### Generated Artifacts

The OpenLane flow produces the following key outputs:

| Stage | Artifact |
|---------|----------|
| Synthesis | Netlist (`.v`) |
| Floorplanning | DEF (`.def`) |
| Placement | Placed DEF |
| CTS | CTS DEF |
| Routing | Routed DEF |
| Signoff | GDSII (`.gds`) |
| Verification | DRC/LVS Reports |

---
