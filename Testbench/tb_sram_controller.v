`timescale 1ns / 1ps

module tb_sram_controller;

  // ===========================================================================
  // Signal Declarations
  // ===========================================================================
  reg          clk;
  reg          rst_n;

  // DUT Inputs
  reg          sram_req;
  reg          sram_we;
  reg  [9:0]   sram_addr;
  reg  [63:0]  sram_wdata;

  // DUT Outputs
  wire [63:0]  sram_rdata;
  wire         sram_ready;
  wire         sram_valid;

  // Verification Variables
  integer      error_count = 0;
  integer      test_count  = 0;
  integer      i;
  
  // Variable for Fuzz Testing
        // Create random 64-bit numbers (Verilog $random only gives 32 bits natively)
      reg [9:0]  rand_addr;
      reg [63:0] rand_data;
      
  // "Golden Model" Memory Array (Used to track randomized expected values)
  reg  [63:0]  expected_mem [0:511];

  // ===========================================================================
  // Device Under Test (DUT) Instantiation
  // ===========================================================================
  sram_controller dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .sram_req   (sram_req),
    .sram_we    (sram_we),
    .sram_addr  (sram_addr),
    .sram_wdata (sram_wdata),
    .sram_rdata (sram_rdata),
    .sram_ready (sram_ready),
    .sram_valid (sram_valid)
  );

  // ===========================================================================
  // Clock Generation (100MHz)
  // ===========================================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // ===========================================================================
  // Verification Tasks (Bus Functional Models)
  // ===========================================================================

  // Task: Hardware Reset
  task apply_reset;
    begin
      rst_n      = 1'b0;
      sram_req   = 1'b0;
      sram_we    = 1'b0;
      sram_addr  = 10'h0;
      sram_wdata = 64'h0;
      
      @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  // Task: Synchronous SRAM Write Transaction
  task sram_write;
    input [9:0]   addr;
    input [63:0]  data;
    input [319:0] test_name;
    begin
      // Wait for SRAM to be ready (Not currently serving a latency read)
      while (!sram_ready) @(posedge clk);
      
      // Drive write signals synchronously
      sram_req   <= 1'b1;
      sram_we    <= 1'b1;
      sram_addr  <= addr;
      sram_wdata <= data;
      
      @(posedge clk);
      
      // De-assert signals
      sram_req   <= 1'b0;
      sram_we    <= 1'b0;
      
      $display("[INFO] %s | Wrote 0x%016X to Addr 0x%03X", test_name, data, addr);
    end
  endtask

  // Task: Synchronous SRAM Read Transaction with Self-Checking
  task sram_read_and_check;
    input [9:0]   addr;
    input [63:0]  expected_data;
    input [319:0] test_name;
    begin
      // Wait for SRAM to be ready
      while (!sram_ready) @(posedge clk);
      
      // Drive read signals
      sram_req  <= 1'b1;
      sram_we   <= 1'b0;
      sram_addr <= addr;
      
      @(posedge clk);
      sram_req <= 1'b0; // De-assert request
      
      // Wait for valid response from the 2-cycle pipeline
      while (!sram_valid) @(posedge clk);
      
      // Check data right after valid asserts
      #1; // Delta cycle delay to ensure non-blocking assignment settled
      test_count = test_count + 1;
      
      if (sram_rdata !== expected_data) begin
        $display("[FAIL] %s | Addr: 0x%03X | Exp: 0x%016X | Act: 0x%016X", 
                 test_name, addr, expected_data, sram_rdata);
        error_count = error_count + 1;
      end else begin
        $display("[PASS] %s | Addr: 0x%03X | Data Matched (0x%016X)", 
                 test_name, addr, sram_rdata);
      end
    end
  endtask


  // ===========================================================================
  // Main Test Sequence
  // ===========================================================================
  initial begin
    $display("===============================================================");
    $display("  STARTING SRAM CONTROLLER VERIFICATION");
    $display("===============================================================");

    // -------------------------------------------------------------------------
    // 1. Reset Initialization Check
    // -------------------------------------------------------------------------
    apply_reset();
    #1; // Delta delay
    test_count = test_count + 1;
    if (sram_ready !== 1'b1 || sram_valid !== 1'b0) begin
      $display("[FAIL] Reset State Verification | Ready: %b, Valid: %b", sram_ready, sram_valid);
      error_count = error_count + 1;
    end else begin
      $display("[PASS] Reset State Verification | SRAM is Ready");
    end

    // -------------------------------------------------------------------------
    // 2. Basic Single Write and Read
    // -------------------------------------------------------------------------
    $display("\n--- Testing Single Write/Read Execution ---");
    sram_write(10'h00A, 64'hDEADBEEF_CAFEBA00, "Basic Single Write");
    sram_read_and_check(10'h00A, 64'hDEADBEEF_CAFEBA00, "Basic Single Read");

    // -------------------------------------------------------------------------
    // 3. Back-to-Back Write Execution
    // -------------------------------------------------------------------------
    $display("\n--- Testing Back-to-Back Writes ---");
    sram_write(10'h001, 64'h11111111_11111111, "B2B Write 1");
    sram_write(10'h002, 64'h22222222_22222222, "B2B Write 2");
    sram_write(10'h003, 64'h33333333_33333333, "B2B Write 3");
    
    sram_read_and_check(10'h001, 64'h11111111_11111111, "Verify B2B Addr 1");
    sram_read_and_check(10'h002, 64'h22222222_22222222, "Verify B2B Addr 2");
    sram_read_and_check(10'h003, 64'h33333333_33333333, "Verify B2B Addr 3");

    // -------------------------------------------------------------------------
    // 4. Latency / Busy Handshake Timing Check
    // -------------------------------------------------------------------------
    $display("\n--- Testing 2-Cycle Latency Handshake Mechanism ---");
    // We initiate a read and check if sram_ready drops immediately to block new requests
    wait(sram_ready);
    @(posedge clk);
    sram_req  <= 1'b1;
    sram_we   <= 1'b0;
    sram_addr <= 10'h001;
    
    @(posedge clk); // Cycle N+1: sram_ready should now be 0 (busy)
    sram_req <= 1'b0;
    #1;
    test_count = test_count + 1;
    if (sram_ready === 1'b0) begin
       $display("[PASS] Handshake Check | SRAM cleanly dropped ready flag during read latency");
    end else begin
       $display("[FAIL] Handshake Check | SRAM failed to drop ready flag");
       error_count = error_count + 1;
    end
    
    // Wait for it to finish and valid to assert
    while (!sram_valid) @(posedge clk);

    // -------------------------------------------------------------------------
    // 5. Randomized Fuzz Testing with Golden Model Verification
    // -------------------------------------------------------------------------
    $display("\n--- Testing Randomized Write/Read Fuzzing ---");
    // Generate 50 random writes across random addresses
    for (i = 0; i < 50; i = i + 1) begin
 
      rand_addr = $random % 512;
      rand_data = { $random, $random }; // Concatenate two 32-bit randoms
      
      // Store in golden model for later verification
      expected_mem[rand_addr] = rand_data;
      
      // Write to actual hardware
      sram_write(rand_addr, rand_data, "Fuzz Write Phase");
    end
    
    // Read them all back using the expected memory model
    $display("[INFO] Randomized Write Phase Complete. Beginning Verification Sweep...");
    for (i = 0; i < 512; i = i + 1) begin
      // Only verify addresses we actually touched (ignore unknown X states)
      if (expected_mem[i] !== 64'hX) begin
        sram_read_and_check(i[9:0], expected_mem[i], "Golden Model Fuzz Read");
      end
    end

    // -------------------------------------------------------------------------
    // Test Summary
    // -------------------------------------------------------------------------
    $display("\n===============================================================");
    $display("  TESTBENCH EXECUTION COMPLETE");
    if (error_count == 0)
      $display("  STATUS: PASSED (%0d/%0d checks passed)", test_count, test_count);
    else
      $display("  STATUS: FAILED (%0d errors out of %0d checks)", error_count, test_count);
    $display("===============================================================");
    $finish;
  end

endmodule