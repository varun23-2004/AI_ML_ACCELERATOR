`timescale 1ns / 1ps

module tb_pe_array_4x4;

  // ===========================================================================
  // Signal Declarations
  // ===========================================================================
  reg          clk;
  reg          rst_n;

  // Flattened Inputs
  reg  [31:0]  activation_in;
  reg  [31:0]  weight_in;
  reg  [3:0]   pe_en;
  reg          clear_acc;
  reg  [1:0]   pe_mode;

  // Flattened Outputs
  wire [63:0]  result_out;
  wire         result_valid;
  wire [3:0]   overflow_flags;

  // Verification Variables
  integer      error_count = 0;
  integer      test_count  = 0;
  integer      i;
  
  // Previous State Tracking (for stall tests)
  reg  [63:0]  prev_result_out;

  // ===========================================================================
  // Device Under Test (DUT)
  // ===========================================================================
  pe_array_4x4 dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .activation_in  (activation_in),
    .weight_in      (weight_in),
    .pe_en          (pe_en),
    .clear_acc      (clear_acc),
    .pe_mode        (pe_mode),
    .result_out     (result_out),
    .result_valid   (result_valid),
    .overflow_flags (overflow_flags)
  );

  // ===========================================================================
  // Clock Generation (100MHz)
  // ===========================================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // ===========================================================================
  // Verification Tasks
  // ===========================================================================

  // Task: Hardware Reset
  task apply_reset;
    begin
      rst_n         = 1'b0;
      activation_in = 32'h0;
      weight_in     = 32'h0;
      pe_en         = 4'b0000;
      clear_acc     = 1'b0;
      pe_mode       = 2'b00; // Default 8-bit mode
      
      @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  // Task: Self-Checking Output Validator
  task check_condition;
    input condition;
    input [319:0] test_name;
    begin
      #1; // Delta cycle delay to allow hardware to settle
      test_count = test_count + 1;
      if (condition) begin
        $display("[PASS] %s", test_name);
      end else begin
        $display("[FAIL] %s | Output: %h, Ovf: %b", test_name, result_out, overflow_flags);
        error_count = error_count + 1;
      end
    end
  endtask

  // ===========================================================================
  // Main Test Sequence
  // ===========================================================================
  initial begin
    $display("===============================================================");
    $display("  STARTING PE ARRAY 4x4 VERIFICATION");
    $display("===============================================================");

    // -------------------------------------------------------------------------
    // 1. Reset Initialization Check
    // -------------------------------------------------------------------------
    apply_reset();
    check_condition((result_out == 64'h0) && (overflow_flags == 4'b0), "Hardware outputs zeroed post-reset");

    // -------------------------------------------------------------------------
    // 2. Data Propagation & Truncation Check
    // -------------------------------------------------------------------------
    $display("\n--- Testing Low-Value Pipeline Propagation ---");
    // We drive small values (1). Since 1*1 = 1, and the PE truncates the output
    // by shifting right 4 bits (accum[19:4]), the output will be 0. 
    // Therefore, the array should eventually output all 0s.
    pe_en         = 4'b1111;
    activation_in = 32'h01010101; 
    weight_in     = 32'h01010101;
    
    // Wait for data to cascade through the 4x4 grid (at least 8-10 cycles)
    for (i = 0; i < 12; i = i + 1) @(posedge clk);
    check_condition((result_out == 64'h0), "Low-value truncation correctly drops to 0 across array");

    // -------------------------------------------------------------------------
    // 3. Saturation & Overflow Stress Test
    // -------------------------------------------------------------------------
    $display("\n--- Testing High-Value Cascading & Saturation ---");
    // Drive max values to rapidly fill the accumulators and force overflows
    activation_in = 32'hFFFFFFFF;
    weight_in     = 32'hFFFFFFFF;
    pe_en         = 4'b1111;

    // FIX: Pump for 25 cycles (instead of 20) to guarantee saturation reaches Column 3
    for (i = 0; i < 25; i = i + 1) @(posedge clk);
    check_condition((overflow_flags !== 4'b0000), "Overflow flags successfully triggered under heavy load");
    check_condition((result_out !== 64'h0), "Result out contains saturated data");

    // -------------------------------------------------------------------------
    // 4. Array Stall Test (Backpressure handling)
    // -------------------------------------------------------------------------
    $display("\n--- Testing Array Stall (pe_en = 0) ---");
    
    // De-assert enable to hit the brakes
    pe_en = 4'b0000;
    
    // FIX (PIPELINE SKID): Wait exactly 1 clock cycle to let data already in Stage 1 flush into Stage 2
    @(posedge clk);
    
    // NOW capture the output state
    #1; prev_result_out = result_out;
    
    // Wait several cycles to prove the array is completely frozen
    for (i = 0; i < 5; i = i + 1) @(posedge clk);
    check_condition((result_out == prev_result_out), "Array successfully stalled, outputs held steady");

    // -------------------------------------------------------------------------
    // 5. Synchronous Global Clear Test
    // -------------------------------------------------------------------------
    $display("\n--- Testing Synchronous Accumulator Clear ---");
    clear_acc = 1'b1;
    @(posedge clk);
    clear_acc = 1'b0;
    
    // Pipeline output stage should reflect clear on the next clock
    @(posedge clk);
    check_condition((result_out == 64'h0) && (overflow_flags == 4'b0), "Global clear successfully zeroed all outputs and flags");

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