`timescale 1ns / 1ps

module tb_accel_ip_top;

  // ===========================================================================
  // 1. System Interface Signal Declarations
  // ===========================================================================
  reg          clk;
  reg          rst_n;

  // AXI4-Lite Write Address Channel
  reg  [15:0]  axi_awaddr;
  reg          axi_awvalid;
  wire         axi_awready;

  // AXI4-Lite Write Data Channel
  reg  [31:0]  axi_wdata;
  reg          axi_wvalid;
  wire         axi_wready;

  // AXI4-Lite Write Response Channel
  wire         axi_bvalid;
  wire [1:0]   axi_bresp;
  reg          axi_bready;

  // AXI4-Lite Read Address Channel
  reg  [15:0]  axi_araddr;
  reg          axi_arvalid;
  wire         axi_arready;

  // AXI4-Lite Read Data Channel
  wire [31:0]  axi_rdata;
  wire         axi_rvalid;
  wire [1:0]   axi_rresp;
  reg          axi_rready;

  // ===========================================================================
  // 2. Verification Global Variables & Constants
  // ===========================================================================
  integer      error_count = 0;
  integer      test_count  = 0;
  integer      timeout_cycles;
  reg [31:0]   status_captured;
  
  // AXI Protocol Constants
  localparam [1:0] OKAY   = 2'b00;
  localparam [1:0] SLVERR = 2'b10;
  
  // Memory-Mapped Register Addresses
  localparam [15:0] ADDR_CTRL        = 16'h0000;
  localparam [15:0] ADDR_BASE_ADDR   = 16'h0004;
  localparam [15:0] ADDR_MATRIX_SIZE = 16'h0008;
  localparam [15:0] ADDR_MODE        = 16'h000C;
  localparam [15:0] ADDR_STATUS      = 16'h0010;
  localparam [15:0] ADDR_CYCLE_COUNT = 16'h0014;
  localparam [15:0] ADDR_ERROR_CODE  = 16'h0018;

  // ===========================================================================
  // 3. Device Under Test (DUT) - Top Level Instantiation
  // ===========================================================================
  accel_ip_top dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .axi_awaddr  (axi_awaddr),
    .axi_awvalid (axi_awvalid),
    .axi_awready (axi_awready),
    .axi_wdata   (axi_wdata),
    .axi_wvalid  (axi_wvalid),
    .axi_wready  (axi_wready),
    .axi_bvalid  (axi_bvalid),
    .axi_bresp   (axi_bresp),
    .axi_bready  (axi_bready),
    .axi_araddr  (axi_araddr),
    .axi_arvalid (axi_arvalid),
    .axi_arready (axi_arready),
    .axi_rdata   (axi_rdata),
    .axi_rvalid  (axi_rvalid),
    .axi_rresp   (axi_rresp),
    .axi_rready  (axi_rready)
  );

  // ===========================================================================
  // 4. Clock Infrastructure (100MHz System Clock)
  // ===========================================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // ===========================================================================
  // 5. Bus Functional Models (BFMs) & Validation Tasks
  // ===========================================================================

  // Task: Synchronous System Reset
  task system_reset;
    begin
      rst_n       = 1'b0;
      axi_awaddr  = 16'h0;
      axi_awvalid = 1'b0;
      axi_wdata   = 32'h0;
      axi_wvalid  = 1'b0;
      axi_bready  = 1'b0;
      axi_araddr  = 16'h0;
      axi_arvalid = 1'b0;
      axi_rready  = 1'b0;
      
      repeat (5) @(posedge clk);
      #1 rst_n = 1'b1; // De-assert slightly off clock edge to simulate real arrival
      repeat (2) @(posedge clk);
      $display("[INFO] System Reset Asserted and Cleared.");
    end
  endtask

  // Task: AXI Master Write Transaction
  task axi_master_write;
    input [15:0]   addr;
    input [31:0]   data;
    input [1:0]    expected_bresp;
    input [319:0]  transaction_description;
    begin
      @(posedge clk);
      axi_awaddr  <= addr;
      axi_awvalid <= 1'b1;
      axi_wdata   <= data;
      axi_wvalid  <= 1'b1;
      axi_bready  <= 1'b1;

      // Address & Data Handshake
      @(posedge clk);
      while (!(axi_awready && axi_wready)) begin
        if (axi_awready) axi_awvalid <= 1'b0;
        if (axi_wready)  axi_wvalid  <= 1'b0;
        @(posedge clk);
      end
      axi_awvalid <= 1'b0;
      axi_wvalid  <= 1'b0;

      // Response Handshake
      while (!axi_bvalid) @(posedge clk);
      
      test_count = test_count + 1;
      if (axi_bresp !== expected_bresp) begin
        $display("[FAIL WRITE] %s | Addr: 0x%04X | Exp BRESP: %b, Act: %b", 
                 transaction_description, addr, expected_bresp, axi_bresp);
        error_count = error_count + 1;
      end else begin
        $display("[PASS WRITE] %s | Addr: 0x%04X", transaction_description, addr);
      end
      
      @(posedge clk);
      axi_bready <= 1'b0;
    end
  endtask

  // Task: AXI Master Read Transaction
  task axi_master_read;
    input [15:0]   addr;
    input [31:0]   expected_rdata;
    input [1:0]    expected_rresp;
    input [319:0]  transaction_description;
    input          ignore_data; // 1'b1 checks protocol response only
    begin
      @(posedge clk);
      axi_araddr  <= addr;
      axi_arvalid <= 1'b1;
      axi_rready  <= 1'b1;

      // Address Handshake
      @(posedge clk);
      while (!axi_arready) @(posedge clk);
      axi_arvalid <= 1'b0;

      // Data Handshake
      while (!axi_rvalid) @(posedge clk);
      
      test_count = test_count + 1;
      if (axi_rresp !== expected_rresp) begin
        $display("[FAIL READ] %s | Addr: 0x%04X | Exp RRESP: %b, Act: %b", 
                 transaction_description, addr, expected_rresp, axi_rresp);
        error_count = error_count + 1;
      end 
      else if (!ignore_data && (axi_rdata !== expected_rdata)) begin
        $display("[FAIL READ] %s | Addr: 0x%04X | Exp Data: 0x%08X, Act: 0x%08X", 
                 transaction_description, addr, expected_rdata, axi_rdata);
        error_count = error_count + 1;
      end 
      else begin
        $display("[PASS READ] %s | Addr: 0x%04X | Data: 0x%08X", transaction_description, addr, axi_rdata);
      end

      @(posedge clk);
      axi_rready <= 1'b0;
    end
  endtask

  // Task: SRAM Backdoor Injection (Pre-load memory without using AXI bus)
  task sram_backdoor_write;
    input [9:0] addr;
    input [63:0] data;
    begin
      // Direct hierarchical assignment bypassing physical ports
      dut.i_sram.sram_mem[addr] = data; 
      $display("[INFO] SRAM Backdoor Write at Addr %0d: 0x%016X", addr, data);
    end
  endtask

  // ===========================================================================
  // 6. Main Integration Test Sequence
  // ===========================================================================
  initial begin
    $display("===============================================================");
    $display("  STARTING ACCEL_IP_TOP SYSTEM INTEGRATION VERIFICATION");
    $display("===============================================================");

    // -------------------------------------------------------------------------
    // TEST SECTION 1: Cold Boot and Reset State Verification
    // -------------------------------------------------------------------------
    system_reset();
    axi_master_read(ADDR_STATUS, 32'h0, OKAY, "Verify STATUS register is idle post-reset", 1'b0);

    // -------------------------------------------------------------------------
    // TEST SECTION 2: Sub-System Configuration & Boundary Tests
    // -------------------------------------------------------------------------
    $display("\n--- Sub-System Configuration Phase ---");
    axi_master_write(ADDR_BASE_ADDR,   32'h00000000, OKAY, "Configure SRAM Base Allocation (Addr 0)");
    axi_master_write(ADDR_MATRIX_SIZE, 32'h00000003, OKAY, "Configure Array Dimension Setting (4x4)");
    axi_master_write(ADDR_MODE,        32'h00000000, OKAY, "Configure Precision Mode (8-bit)");

    $display("\n--- System Boundary Protocol Testing ---");
    // Attempting write access to Read-Only Status Space (Checks SLVERR trapping)
    axi_master_write(ADDR_STATUS, 32'hFFFFFFFF, SLVERR, "Trap malicious write attempt to RO Status Register");

    // -------------------------------------------------------------------------
    // TEST SECTION 3: Backdoor Memory Preloading
    // -------------------------------------------------------------------------
    $display("\n--- Preloading SRAM Data via Testbench Backdoor ---");
    // Preload addresses 0-3 with dummy activation/weight data (e.g., 01, 02, etc.)
    sram_backdoor_write(10'd0, 64'h01010101_01010101);
    sram_backdoor_write(10'd1, 64'h02020202_02020202);
    sram_backdoor_write(10'd2, 64'h01010101_01010101);
    sram_backdoor_write(10'd3, 64'h02020202_02020202);
    // Clear out address 4, where the FSM is hardcoded to write the final result back
    sram_backdoor_write(10'd4, 64'h00000000_00000000); 

    // -------------------------------------------------------------------------
    // TEST SECTION 4: End-to-End Execution Sequence
    // -------------------------------------------------------------------------
    $display("\n--- Launching Full Array Execution Loop ---");
    
    // Assert Execution Token (START = 0x01)
    axi_master_write(ADDR_CTRL, 32'h00000001, OKAY, "Assert Execution Token [START=0x01] to CTRL");

    // Polling System Status until DONE bit (bit 0) asserts
    $display("[INFO] Polling Accelerator Status for Completion...");
    timeout_cycles = 0;
    status_captured = 32'h0;
    
    while ((status_captured[0] == 1'b0) && (timeout_cycles < 200)) begin
      repeat (5) @(posedge clk); // Poll every 5 cycles
      timeout_cycles = timeout_cycles + 5;
      
      axi_master_read(ADDR_STATUS, 32'h0, OKAY, "Polling Status Register...", 1'b1);
      status_captured = axi_rdata; 
    end
    
    test_count = test_count + 1;
    if (status_captured[0] == 1'b1) begin
      $display("[PASS STATUS] Compute cycle completed successfully in %0d system cycles.", timeout_cycles);
    end else begin
      $display("[FAIL STATUS] Accelerator execution timed out (Watchdog triggered).");
      error_count = error_count + 1;
    end

    // -------------------------------------------------------------------------
    // TEST SECTION 5: Memory Writeback Validation (Result Checking)
    // -------------------------------------------------------------------------
    $display("\n--- Verifying SRAM Result Writeback via Backdoor ---");
    // FSM writes to (Base Addr + 4) -> So we check dut.i_sram.sram_mem[4]
    test_count = test_count + 1;
    #1; // Delta delay
    if (dut.i_sram.sram_mem[4] !== 64'h00000000_00000000) begin
      $display("[PASS RESULT] FSM successfully wrote computed matrix to SRAM Addr 4: 0x%016X", dut.i_sram.sram_mem[4]);
    end else begin
      $display("[FAIL RESULT] FSM failed to write back data, SRAM Addr 4 is empty.");
      error_count = error_count + 1;
    end

    // -------------------------------------------------------------------------
    // TEST SECTION 6: Post-Execution Cleanup (Clear Strobe)
    // -------------------------------------------------------------------------
    $display("\n--- System Reset-Strobe Operations Test ---");
    axi_master_write(ADDR_CTRL, 32'h00000004, OKAY, "Assert Register Clear Command [CLEAR=0x04]");
    axi_master_read(ADDR_STATUS, 32'h0, OKAY, "Verify STATUS dropped back to IDLE (0)", 1'b0);

    // ===========================================================================
    // 7. Simulation Summary Report
    // ===========================================================================
    $display("\n===============================================================");
    $display("  TOP-LEVEL SYSTEM VERIFICATION PHASE COMPLETED");
    if (error_count == 0)
      $display("  GLOBAL STATUS: PASSED (%0d/%0d Integration Checks Successful)", test_count, test_count);
    else
      $display("  GLOBAL STATUS: FAILED (%0d Errors Identified in System Topology)", error_count, test_count);
    $display("===============================================================");
    $finish;
  end

endmodule