`timescale 1ns / 1ps

module tb_processing_element;

  // -------------------------------------------------------------------------
  // Signal Declarations
  // -------------------------------------------------------------------------
  reg          clk;
  reg          rst_n;
  reg  [7:0]   act;
  reg  [7:0]   wt;
  reg          pe_en;
  reg          clear_acc;
  reg  [1:0]   pe_mode;
  
  wire [15:0]  out;
  wire         overflow;

  // -------------------------------------------------------------------------
  // Testbench Variables
  // -------------------------------------------------------------------------
  integer error_count = 0;
  integer test_count  = 0;
  integer i;

  // -------------------------------------------------------------------------
  // Device Under Test (DUT) Instantiation
  // -------------------------------------------------------------------------
  processing_element dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .act        (act),        
    .wt         (wt),         
    .pe_en      (pe_en),      
    .clear_acc  (clear_acc),  
    .pe_mode    (pe_mode),    
    .out        (out),        
    .overflow   (overflow)    
  );

  // -------------------------------------------------------------------------
  // Clock Generation (100MHz)
  // -------------------------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk; 
  end

  // -------------------------------------------------------------------------
  // Verification Tasks
  // -------------------------------------------------------------------------
  
  // Task: Asynchronous Reset Application
  task apply_reset;
    begin
      rst_n     = 1'b0;
      act       = 8'h0;
      wt        = 8'h0;
      pe_en     = 1'b0;
      clear_acc = 1'b0;
      pe_mode   = 2'b00; // Default 8-bit mode
      @(posedge clk);
      @(negedge clk);
      rst_n     = 1'b1;
      @(posedge clk);
    end
  endtask

  // Task: Self-Checking Output Validator
  task check_result;
    input [19:0] expected_accum;
    input        expected_ovf;
    input [128:8] test_name;
    reg   [15:0] expected_out;
    begin
      #1; // DELTA CYCLE FIX: Wait 1ns for DUT non-blocking assignments to settle
      
      // DUT takes accum[19:4] for the output register
      expected_out = expected_accum[19:4]; 
      
      test_count = test_count + 1;
      if (out !== expected_out || overflow !== expected_ovf) begin
        $display("[FAIL] %s | Expected Out: 0x%04X, Ovf: %b | Actual Out: 0x%04X, Ovf: %b", 
                 test_name, expected_out, expected_ovf, out, overflow);
        error_count = error_count + 1;
      end else begin
        $display("[PASS] %s | Out: 0x%04X, Ovf: %b", test_name, out, overflow);
      end
    end
  endtask

  // -------------------------------------------------------------------------
  // Main Test Sequence
  // -------------------------------------------------------------------------
  initial begin
    $display("===============================================================");
    $display("  STARTING PE MODULE VERIFICATION");
    $display("===============================================================");

    // 1. Reset Initialization
    apply_reset();
    
    // 2. Basic 8-bit MAC Operation
    @(posedge clk);
    pe_en   = 1'b1;
    pe_mode = 2'b00; 
    act     = 8'd10;
    wt      = 8'd5;
    @(posedge clk); // Stage 1: Input capture
    act     = 8'd0;
    wt      = 8'd0;
    pe_en   = 1'b0;
    @(posedge clk); // Stage 2: Output generation
    check_result(20'd50, 1'b0, "Basic 8x8 MAC (10 * 5 = 50)");

    // 3. Stall Testing (pe_en toggling)
    @(posedge clk);
    act     = 8'hFF;
    wt      = 8'hFF;
    pe_en   = 1'b0; // STALL
    @(posedge clk);
    @(posedge clk);
    check_result(20'd50, 1'b0, "Stall Test (pe_en = 0)");

    // 4. Quantization Mode: 4-bit Testing
    @(posedge clk);
    pe_en   = 1'b1;
    pe_mode = 2'b01; // 4-bit mode
    act     = 8'hF3; // Lower 4 bits = 3
    wt      = 8'hF4; // Lower 4 bits = 4
    @(posedge clk);
    pe_en   = 1'b0;
    @(posedge clk);
    check_result(20'd62, 1'b0, "4x4 Mode MAC (act[3:0]*wt[3:0])");

    // 5. Synchronous Clear Accumulator
    @(posedge clk);
    clear_acc = 1'b1; // Clear flag
    @(posedge clk);
    clear_acc = 1'b0;
    @(posedge clk);
    check_result(20'd0, 1'b0, "Clear Accumulator Test");

    // 6. Saturation and Overflow Testing
    $display("--- Starting Saturation Stress Test ---");
    pe_en   = 1'b1;
    pe_mode = 2'b00;
    act     = 8'hFF;
    wt      = 8'hFF;
    
    // Pump MAC for 17 cycles to force saturation
    for (i = 0; i < 17; i = i + 1) begin
      @(posedge clk);
    end
    pe_en = 1'b0;
    @(posedge clk);
    check_result(20'hFFFFF, 1'b1, "Saturation & Overflow Trigger");

    // 7. Randomized Testing
    $display("--- Starting Randomized Combinational Testing ---");
    apply_reset();
    pe_en = 1'b1;
    pe_mode = 2'b00;
    
    for (i = 0; i < 20; i = i + 1) begin
      @(negedge clk); 
      act = $random % 256;
      wt  = $random % 256;
    end
    @(posedge clk);
    pe_en = 1'b0;
    @(posedge clk);
    $display("[INFO] Completed 20 cycles of randomized stimulus.");

    // -------------------------------------------------------------------------
    // Test Summary
    // -------------------------------------------------------------------------
    $display("===============================================================");
    $display("  TESTBENCH EXECUTION COMPLETE");
    if (error_count == 0)
      $display("  STATUS: PASSED (%0d/%0d checks passed)", test_count, test_count);
    else
      $display("  STATUS: FAILED (%0d errors out of %0d checks)", error_count, test_count);
    $display("===============================================================");
    $finish;
  end

endmodule