`timescale 1ns/1ps

module tb_array_controller_fsm;

  // Inputs
  reg clk;
  reg rst_n;

  reg [7:0]  cmd;
  reg [15:0] base_addr;
  reg [1:0]  matrix_size;
  reg [1:0]  quantization_mode;

  reg         pe_result_valid;
  reg [255:0] pe_result;
  reg [3:0]   pe_overflow;

  reg [15:0] pe_result_0;
  reg [15:0] pe_result_1;
  reg [15:0] pe_result_2;
  reg [15:0] pe_result_3;

  reg [63:0] sram_rdata;
  reg        sram_ready;
  reg        sram_valid;

  // Outputs
  wire [3:0]  pe_en;
  wire        pe_clear_acc;
  wire [1:0]  pe_mode;

  wire        sram_req;
  wire        sram_we;
  wire [9:0]  sram_addr;
  wire [63:0] sram_wdata;

  wire        status_done;
  wire        status_busy;
  wire        status_error;
  wire        status_overflow;

  wire [31:0] cycle_count;
  wire [31:0] error_code;

  // DUT Instantiation
  array_controller_fsm dut (
    .clk(clk),
    .rst_n(rst_n),

    .cmd(cmd),
    .base_addr(base_addr),
    .matrix_size(matrix_size),
    .quantization_mode(quantization_mode),

    .pe_en(pe_en),
    .pe_clear_acc(pe_clear_acc),
    .pe_mode(pe_mode),

    .pe_result_valid(pe_result_valid),
    .pe_result(pe_result),
    .pe_overflow(pe_overflow),

    .pe_result_0(pe_result_0),
    .pe_result_1(pe_result_1),
    .pe_result_2(pe_result_2),
    .pe_result_3(pe_result_3),

    .sram_req(sram_req),
    .sram_we(sram_we),
    .sram_addr(sram_addr),
    .sram_wdata(sram_wdata),

    .sram_rdata(sram_rdata),
    .sram_ready(sram_ready),
    .sram_valid(sram_valid),

    .status_done(status_done),
    .status_busy(status_busy),
    .status_error(status_error),
    .status_overflow(status_overflow),

    .cycle_count(cycle_count),
    .error_code(error_code)
  );

  // Clock Generation
  always #5 clk = ~clk;

  // Test Procedure
  initial begin

    // Initialize
    clk = 0;
    rst_n = 0;

    cmd = 0;
    base_addr = 16'h0010;
    matrix_size = 2'b11;
    quantization_mode = 2'b00;

    pe_result_valid = 0;
    pe_result = 0;
    pe_overflow = 0;

    pe_result_0 = 16'h1111;
    pe_result_1 = 16'h2222;
    pe_result_2 = 16'h3333;
    pe_result_3 = 16'h4444;

    sram_rdata = 64'hAAAA_BBBB_CCCC_DDDD;
    sram_ready = 0;
    sram_valid = 0;

    // Reset
    #20;
    rst_n = 1;

    // START command
    #10;
    cmd = 8'h01;

    // SRAM ready responses
    repeat(4) begin
      #10;
      sram_ready = 1;
      sram_valid = 1;

      #10;
      sram_ready = 0;
      sram_valid = 0;
    end

    // PE result valid
    #30;
    pe_result_valid = 1;

    #10;
    pe_result_valid = 0;

    // Wait for DONE state
    #100;

    // CLEAR command
    cmd = 8'h04;

    #20;

    $finish;
  end

  // Monitor Signals
  initial begin
    $monitor(
      "TIME=%0t | STATE INFO -> BUSY=%b DONE=%b ERROR=%b PE_EN=%b SRAM_REQ=%b SRAM_WE=%b ADDR=%h",
      $time,
      status_busy,
      status_done,
      status_error,
      pe_en,
      sram_req,
      sram_we,
      sram_addr
    );
  end

endmodule
