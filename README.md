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


