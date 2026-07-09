`timescale 1ns / 1ps

module tb_processing_element;

  // Signal Declarations
  reg clk;
  reg rst_n;
  reg [7:0] act;
  reg [7:0] wt;
  reg      pe_en;
  reg      clear_acc;
  reg [1:0] pe_mode;
  
  wire [15:0] out;
  wire       overflow;

  wire [7:0] act_out;
  wire [7:0] wt_out

  // Testbench Variables
  integer error_count = 0;
  integer test_count  = 0;
  integer i;
  integer errors_before;

  // Device Under Test (DUT) Instantiation
  processing_element dut (
    .clk (clk),
    .rst_n (rst_n),
    .act (act),        
    .wt (wt),         
    .pe_en (pe_en),      
    .clear_acc (clear_acc),  
    .pe_mode (pe_mode),    
    .out (out),        
    .overflow (overflow),
    .act_out (act_out),
    .wt_out (wt_out)    
  );

  // Clock Generation (100MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk; 
  end

  // Verification Tasks
  
  // Task: Asynchronous Reset Application
  task apply_reset;
    begin
      rst_n = 1'b0;
      act = 8'h0;
      wt = 8'h0;
      pe_en = 1'b0;
      clear_acc = 1'b0;
      pe_mode = 2'b00; // Default 8-bit mode
      @(posedge clk);
      @(negedge clk);
      rst_n  = 1'b1;
      @(posedge clk);
    end
  endtask

  // Task: Self-Checking Output Validator
  task check_result;
    input [19:0]expected_accum;
    input       expected_ovf;
    input [8*32:8]test_name;
    reg   [15:0] expected_out;
    begin
      #1; 
      
      // DUT takes accum[19:4] for the output register
      if(expected_ovf)
        expected_out = 16'hFFFF;
      else
        expected_out = expected_accum[19:4];


      test_count = test_count + 1;
      if (out !== expected_out || overflow !== expected_ovf) begin
        $display("[FAIL] %s | Expected Out: 0x%04X, Ovf: %b | Actual Out: 0x%04X, Ovf: %b", 
                 test_name, expected_out, expected_ovf, out, overflow);
        error_count = error_count + 1;
      end else begin
        $display("[PASS] %s | Out: 0x%04X, Ovf: %b", test_name, out, overflow);
      end
      $display("DEBUG accum = %0d", dut.accum);
    end
  endtask

  //Task: pass through checker task
  task check_passthrough;
        input [7:0] exp_act;
        input [7:0] exp_wt;
    begin
      #1;
      test_count = test_count +1;

      if(act_out !== exp_act || wt_out !== exp_wt)
      begin
          $display("[FAIL] Pass-through | exp_act=%0d act_out=%0d exp_wt=%0d wt_out=%0d",
                    exp_act, act_out, exp_wt, wt_out);
          error_count = error_count + 1;
      end
      else
        $display("[PASS] Pass-through success ");
    end
  endtask

  task start_test;
  input [8*20:1] test_name;
  begin
    $display("");
    $display("================================================================================");
    $display("[STARTED] %s", test_name);
    errors_before = error_count;
  end
  endtask

  task finish_test;
  input [8*20:1] test_name;
  begin
    $display("");
    if(error_count == errors_before)
    begin 
      $display("[PASS] %s", test_name);
    end
    else 
    begin
      $display("[FAIL] %s", test_name);
    end
    $display("[FINISHED] %s", test_name);
    $display("================================================================================");
  end
  endtask

  task clear_accumulator;
  begin

      clear_acc = 1'b1;
      @(posedge clk);

      clear_acc = 1'b0;
      @(posedge clk);

  end
  endtask

  // Main Test Sequence
  initial begin
    $display("===============================================================");
    $display("  STARTING PE MODULE VERIFICATION");
    $display("===============================================================");

    // 1. Reset Initialization
    $display("---- RESET INITIALIZATION STARTED ---");
    apply_reset();
    $display("---- RESET INITIALIZATION FINISHED ---");
   
   
    // 2. Calling Pass Through 
    start_test("Pass Through Test");
    @(posedge clk);
    pe_en = 1;
    act = 8'd55;
    wt = 8'd99;
    @(posedge clk);
    check_passthrough (8'd55, 8'd99);
    finish_test("Pass Through Test");
    
    //3. Basic 8-bit MAC Operation
    start_test("Test 1: Mode 8X8 ");
    pe_en = 0;
    act = 0;
    wt = 0;
    clear_accumulator();
    @(posedge clk);
    pe_en = 1'b1;
    pe_mode = 2'b00; 
    act = 8'd10;
    wt = 8'd5;
    @(posedge clk); // Stage 1: Input capture
    act = 8'd0;
    wt = 8'd0;
    pe_en = 1'b0;
    @(posedge clk); // Stage 2: Output generation
    check_result(20'd50, 1'b0, "Basic 8x8 MAC (10 * 5 = 50)");
    finish_test("Test 1: Mode 8X8 ");    


    //4. Stall Testing (pe_en toggling)
    start_test("Stall Testing");
    clear_accumulator();
    @(posedge clk);
    act = 8'hFF;
    wt = 8'hFF;
    pe_en = 1'b0; // STALL
    @(posedge clk);
    @(posedge clk);
    check_result(20'd0, 1'b0, "Stall Test (pe_en = 0)");
    finish_test("Stall Testing");

    // 5. Quantization Mode: 4-bit Testing
    start_test("Test 2: Mode 4X4 ");
    clear_accumulator();
    @(posedge clk);
    pe_en = 1'b1;
    pe_mode = 2'b01; // 4-bit mode
    act = 8'hF3; // Lower 4 bits = 3
    wt = 8'hF4; // Lower 4 bits = 4
    @(posedge clk);
    pe_en = 1'b0;
    @(posedge clk);
    check_result(20'd12, 1'b0, "4x4 Mode MAC (act[3:0]*wt[3:0])");
    finish_test("Test 2: Mode 4X4 ");

    //6. Quantization Mode: 4x8 Testing 
    start_test("Test 3: Mode 4X8");
    clear_accumulator();
    @(posedge clk);
    pe_en = 1'b1;
    pe_mode = 2'b10;
    act = 8'hF5;
    wt = 8'd10;
    @(posedge clk);
    pe_en = 1'b0;
    @(posedge clk);
    check_result(20'd50, 1'b0, "4x8 Mode MAC (act[3:0]*wt[7:0])");
    finish_test("Test 3: Mode 4X8");


    //7. Quantization Mode: 8x8 Testing (pe_mode = 11)
    start_test("Test 4: Mode 11");
    clear_accumulator();
    @(posedge clk);
    pe_en = 1'b1;
    pe_mode = 2'b11;
    act = 8'd4;
    wt = 8'd5;
    @(posedge clk);
    pe_en = 1'b0;
    @(posedge clk);
    check_result(20'd20, 1'b0, "8x8 Mode MAC (act[7:0]*wt[7:0])");
    finish_test("Test 4: Mode 11");

    // 8. Synchronous Clear Accumulator
    start_test("Clear Accumulator");   
    @(posedge clk);
    clear_acc = 1'b1; // Clear flag
    @(posedge clk);
    clear_acc = 1'b0;
    @(posedge clk);
    check_result(20'd0, 1'b0, "Clear Accumulator Test");
    finish_test("Clear Accumulator");


    // 9. Saturation and Overflow Testing
    start_test("Saturation and Overflow");
    clear_accumulator();
    pe_en = 1'b1;
    pe_mode = 2'b00;
    act = 8'hFF;
    wt = 8'hFF;

    for(i=0;i<17;i=i+1)
    begin
      @(posedge clk);
    end
    pe_en = 1'b0;
    @(posedge clk);

    check_result(20'hFFFFF,1'b1,"Saturation & Overflow Trigger");
    finish_test("Saturation and Overflow");


// 10. Sticky Overflow 
    start_test("Sticky Overflow");
    @(posedge clk);
    pe_en = 1'b1;
    act = 8'd1;
    wt = 8'd1;
    @(posedge clk);
    pe_en = 1'b0;
    @(posedge clk);
    test_count = test_count + 1;
    if(overflow != 1'b1)
    begin
        $display("[FAIL] Sticky Overflow");
        error_count = error_count + 1;
    end
    else
    begin
        $display("[PASS] Sticky Overflow");
    end
    finish_test("Sticky Overflow");


    // 7. Randomized Testing
    start_test("Random Stimulus");
    apply_reset();
    pe_en = 1'b1;
    pe_mode = 2'b00;
    
    for (i = 0; i < 20; i = i + 1) begin
      @(negedge clk); 
      act = $urandom_range (0,255);
      wt  = $urandom_range (0,255);
    end
    @(posedge clk);
    pe_en = 1'b0;
    @(posedge clk);
    $display("[INFO] Completed 20 cycles of randomized stimulus.");
    finish_test("Random Stimulus");

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