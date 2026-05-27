//==============================================================================
// Module: sram_controller
// Purpose: Dual-port SRAM wrapper (512 locations × 64-bit = 4KB)
// Read port: 2-cycle latency (async address, registered output)
// Write port: Synchronous write (immediate)
// Interface: Ready/valid handshakes for both read and write operations
// Memory organization: 512 × 64-bit (can be configured for 8 × 8-bit or 4 × 16-bit)
//==============================================================================

module sram_controller (
  input                clk,
  input                rst_n,
  input                sram_req,           // Initiate read or write request
  input                sram_we,            // Write enable (0=read, 1=write)
  input        [9:0]   sram_addr,          // 10-bit address (512 locations)
  input        [63:0]  sram_wdata,         // 64-bit write data
  output       [63:0]  sram_rdata,         // 64-bit read data (registered)
  output               sram_ready,         // Ready for next request
  output               sram_valid          // Read data valid strobe
);

  // SRAM memory array: 512 locations × 64 bits
  reg [63:0]  sram_mem [0:511];
  
  // Read pipeline stages for 2-cycle latency
  reg [9:0]   read_addr_r1;               // Cycle 1: capture address
  reg [63:0]  read_data_r2;               // Cycle 2: register SRAM output
  
  // Control pipeline
  reg         read_valid_r1;              // Cycle 1: read request valid
  reg         read_valid_r2;              // Cycle 2: output valid (sram_valid)
  
  // State tracking
  reg         sram_busy_r;                // Busy flag during read latency
  
  // Output assignments
  assign sram_rdata = read_data_r2;
  assign sram_valid = read_valid_r2;
  assign sram_ready = ~sram_busy_r;
  
  //----------------------------------------------------------------------------
  // Request Handling: Latch request type and address
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sram_busy_r  <= 1'b0;
      read_valid_r1 <= 1'b0;
      read_addr_r1 <= 10'h0;
    end
    else begin
      if (sram_req && !sram_busy_r) begin
        // New request accepted
        if (!sram_we) begin
          // Read request
          sram_busy_r   <= 1'b1;          // Occupy for 2 cycles
          read_valid_r1 <= 1'b1;
          read_addr_r1  <= sram_addr;
        end
        else begin
          // Write request (completes immediately, no busy extension)
          sram_busy_r   <= 1'b0;
          read_valid_r1 <= 1'b0;
        end
      end
      else if (sram_busy_r) begin
        // Busy countdown: after 2 cycles, release
        sram_busy_r   <= 1'b0;
        read_valid_r1 <= 1'b0;
      end
    end
  end
  
  //----------------------------------------------------------------------------
  // Read Latency Stage 1: Async SRAM read
  // Reads data from memory based on previously latched address
  //----------------------------------------------------------------------------
  wire [63:0] sram_read_w = sram_mem[read_addr_r1];
  
  //----------------------------------------------------------------------------
  // Read Latency Stage 2: Register SRAM output
  // Creates the second cycle of read latency
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_data_r2  <= 64'h0;
      read_valid_r2 <= 1'b0;
    end
    else begin
      // Pipeline stage 2: register the read data
      read_data_r2  <= sram_read_w;
      read_valid_r2 <= read_valid_r1;    // Shift valid flag 1 cycle
    end
  end
  
  //----------------------------------------------------------------------------
  // Write Operation: Synchronous write on rising clock
  // Completes immediately (within 1 cycle), does not assert busy
  //----------------------------------------------------------------------------
  always @(posedge clk) begin
    if (sram_req && sram_we) begin
      sram_mem[sram_addr] <= sram_wdata;
    end
  end
  
  //----------------------------------------------------------------------------
  // Optional: Initialize SRAM with default values (for simulation/verification)
  // In synthesis, this section can be removed or replaced with SRAM initialization file
  //----------------------------------------------------------------------------
  integer i;
  initial begin
    for (i = 0; i < 512; i = i + 1)
      sram_mem[i] = 64'h0;
  end

endmodule