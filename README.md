# AHB-Lite-Master-Design
This repository contains a synthesizable **AMBA AHB-Lite Master** module written in Verilog along with a comprehensive **testbench**.   The design demonstrates a functional AHB-Lite master capable of performing **single** and **burst read/write** transfers, complete with handshake and response handling.

This project implements a parameterized **AHB-Lite Master** suitable for SoC and FPGA integration.  
It features:
- Configurable **address** and **data width**
- **Single** and **INCR burst** transfer modes
- Proper handling of **HREADY** and **HRESP**
- Simple **command interface** for CPU/testbench integration
- Clean and modular FSM design (IDLE → ADDR → DATA → IDLE)
- Comprehensive testbench with:
  - Single & burst transfers
  - Wait state insertion
  - Error response testing
 
    
