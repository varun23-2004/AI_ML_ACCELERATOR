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

**End-to-End Silicon Implementation**: To design, verify, and physically implement a complex AI/ML hardware accelerator, driving the design from behavioral RTL down to a routable 
GDSII layout using the OpenLane EDA flow.

**Scalable Compute Architecture**: To architect a 4x4 systolic array capable of performing highly parallel, variable-precision (8-bit and 4-bit) Multiply-Accumulate (MAC) 
operations for efficient neural network inference.

**Industry-Standard SoC Integration**: To ensure the IP is ready for seamless integration into modern System-on-Chip (SoC) environments by designing a compliant AXI4-Lite slave interface and 
an integrated dual-port SRAM for local data buffering.

**PPA Optimization and Signoff**: To target the SkyWater 130nm (Sky130A) technology node and successfully achieve a clean physical design signoff (Zero DRC/LVS violations) while meeting strict Power, Performance, and Area constraints.

## 3. Key Objectives 

**4x4 Systolic Processing Array**: Executes highly parallel Multiply-Accumulate (MAC) operations with spatial data reuse, maximizing computational throughput for neural network matrix multiplications

**Configurable Quantization Modes**: Supports dynamic switching between 8-bit and 4-bit integer precision, allowing software to double the computation throughput when lower dynamic range is sufficient.

**Integrated Dual-Port SRAM**: Internal 4KB (512 x 64-bit) memory block decouples the systolic array from external bus latency, providing continuous, high-bandwidth streaming of weights and activations.

**Hardware State Machine Orchestration**: A centralized Array Controller FSM independently manages weight fetching, systolic execution, and result draining, minimizing host CPU overhead.

**Standard AMBA AXI4-Lite Protocol**: Features a compliant memory-mapped slave interface dedicated to configuring computation parameters (base address, matrix size) and polling execution status.

## 4. System Architecture 
The AI/ML Accelerator is highly modular, strictly separating the control plane (bus interfacing and state management) from the datapath (computation and memory). It uses a top-level wrapper, [accel_ip_top](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/accel_ip_top.v), to integrate five core sub-modules.

**A. Top-Level Integration: [accel_ip_top](https://github.com/varun23-2004/AI_ML_ACCELERATOR/blob/main/RTL_Design/accel_ip_top.v)
This is the physical and logical wrapper of the IP. It acts as the central hub, mapping external SoC signals to the internal sub-systems.

Signal Routing: It directly wires the configuration outputs from the AXI4-Lite Slave into the FSM, and routes the memory/compute signals between the FSM, the SRAM, and the PE Array.

Data Unpacking: It handles the continuous 64-bit data streams coming from the SRAM and unpacks them into discrete 8-bit activation and weight buses to feed the systolic rows.
