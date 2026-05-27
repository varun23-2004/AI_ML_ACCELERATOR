`timescale 1ns/1ps

module tb_axi4_lite_slave;

  // Clock and Reset
  reg clk;
  reg rst_n;

  // AXI Write Address Channel
  reg  [15:0] axi_awaddr;
  reg         axi_awvalid;
  wire        axi_awready;

  // AXI Write Data Channel
  reg  [31:0] axi_wdata;
  reg         axi_wvalid;
  wire        axi_wready;

  // AXI Write Response Channel
  wire        axi_bvalid;
  wire [1:0]  axi_bresp;
  reg         axi_bready;

  // AXI Read Address Channel
  reg  [15:0] axi_araddr;
  reg         axi_arvalid;
  wire        axi_arready;

  // AXI Read Data Channel
  wire [31:0] axi_rdata;
  wire        axi_rvalid;
  wire [1:0]  axi_rresp;
  reg         axi_rready;

  // Outputs
  wire [7:0]  ctrl_cmd;
  wire [15:0] base_addr;
  wire [1:0]  matrix_size;
  wire [1:0]  quantization_mode;
  wire        ctrl_write_valid;

  // Status Inputs
  reg         status_done;
  reg         status_busy;
  reg         status_error;
  reg         status_overflow;
  reg [31:0]  cycle_count;
  reg [31:0]  error_code;
  
  // --- NEW: Verification Trackers ---
  integer error_count = 0;
  integer test_count  = 0;

  // DUT Instantiation
  axi4_lite_slave dut (
    .clk(clk),
    .rst_n(rst_n),

    .axi_awaddr(axi_awaddr),
    .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready),

    .axi_wdata(axi_wdata),
    .axi_wvalid(axi_wvalid),
    .axi_wready(axi_wready),

    .axi_bvalid(axi_bvalid),
    .axi_bresp(axi_bresp),
    .axi_bready(axi_bready),

    .axi_araddr(axi_araddr),
    .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready),

    .axi_rdata(axi_rdata),
    .axi_rvalid(axi_rvalid),
    .axi_rresp(axi_rresp),
    .axi_rready(axi_rready),

    .ctrl_cmd(ctrl_cmd),
    .base_addr(base_addr),
    .matrix_size(matrix_size),
    .quantization_mode(quantization_mode),
    .ctrl_write_valid(ctrl_write_valid),

    .status_done(status_done),
    .status_busy(status_busy),
    .status_error(status_error),
    .status_overflow(status_overflow),
    .cycle_count(cycle_count),
    .error_code(error_code)
  );

  // Clock Generation
  always #5 clk = ~clk;

  // AXI Write Task with Self-Checking
  task axi_write;
    input [15:0] addr;
    input [31:0] data;
    input [1:0]  expected_bresp; // <-- ADD THIS INPUT
    begin
      @(posedge clk);

      axi_awaddr  <= addr;
      axi_awvalid <= 1'b1;
      axi_wdata   <= data;
      axi_wvalid  <= 1'b1;

      axi_bready  <= 1'b1;

      @(posedge clk);

      axi_awvalid <= 1'b0;
      axi_wvalid  <= 1'b0;

      wait(axi_bvalid);
      
      // Verification Logic
      test_count = test_count + 1;
      if (axi_bresp !== expected_bresp) begin
        $display("[FAIL] WRITE ADDR = %h | Exp Resp: %b | Act Resp: %b", 
                  addr, expected_bresp, axi_bresp);
        error_count = error_count + 1;
      end else begin
        $display("[PASS] WRITE ADDR = %h | Resp: %b", addr, axi_bresp);
      end

      @(posedge clk);
      axi_bready <= 1'b0;
    end
  endtask
  // --- MODIFIED: AXI Read Task with Self-Checking ---
  task axi_read;
    input [15:0] addr;
    input [31:0] expected_data;
    input [1:0]  expected_resp;
    begin
      @(posedge clk);

      axi_araddr  <= addr;
      axi_arvalid <= 1'b1;
      axi_rready  <= 1'b1;

      @(posedge clk);

      axi_arvalid <= 1'b0;

      wait(axi_rvalid);
      
      // Verification Logic
      test_count = test_count + 1;
      if (axi_rdata !== expected_data || axi_rresp !== expected_resp) begin
        $display("[FAIL] READ ADDR = %h | Exp Data: %h (Resp: %b) | Act Data: %h (Resp: %b)", 
                  addr, expected_data, expected_resp, axi_rdata, axi_rresp);
        error_count = error_count + 1;
      end else begin
        $display("[PASS] READ ADDR = %h | Data: %h (Resp: %b)", addr, axi_rdata, axi_rresp);
      end

      @(posedge clk);
      axi_rready <= 1'b0;
    end
  endtask

  // Test Sequence
  initial begin

    // Initialize
    clk = 0;
    rst_n = 0;

    axi_awaddr  = 0;
    axi_awvalid = 0;

    axi_wdata   = 0;
    axi_wvalid  = 0;
    axi_bready  = 0;

    axi_araddr  = 0;
    axi_arvalid = 0;

    axi_rready  = 0;
    
    // Status signals setup (Done=0, Busy=1, Error=0, Overflow=0 -> 4'b0010 = 2)
    status_done     = 0;
    status_busy     = 1;
    status_error    = 0;
    status_overflow = 0;

    cycle_count = 32'h00001234;
    error_code  = 32'hDEAD_BEEF;

    // Reset
    #20;
    rst_n = 1;
    
    // -----------------------------
    // WRITE OPERATIONS
    // -----------------------------
    $display("---Starting Write Operation----");
    // CTRL Register
    axi_write(16'h0000, 32'h00000001, 2'b00);
    // BASE_ADDR Register
    axi_write(16'h0004, 32'h00001000, 2'b00);
    // MATRIX_SIZE Register
    axi_write(16'h0008, 32'h00000002, 2'b00);
    // MODE Register
    axi_write(16'h000C, 32'h00000001, 2'b00);

    // -----------------------------
    // READ OPERATIONS (Self-Checking)
    // -----------------------------
    $display("--- Starting Read Verifications ---");
    
    // Config Registers (Expecting 2'b00 OKAY response)
    axi_read(16'h0000, 32'h00000001, 2'b00);
    axi_read(16'h0004, 32'h00001000, 2'b00);
    axi_read(16'h0008, 32'h00000002, 2'b00);
    axi_read(16'h000C, 32'h00000001, 2'b00);

    // Status Register (Busy is 1, so status = 2)
    axi_read(16'h0010, 32'h00000002, 2'b00);
    // Cycle Count Register
    axi_read(16'h0014, 32'h00001234, 2'b00);
    // Error Code Register
    axi_read(16'h0018, 32'hDEAD_BEEF, 2'b00);

    // Invalid Address Test (Expecting 32'h0 and 2'b10 SLVERR response)
    axi_read(16'h0020, 32'h00000000, 2'b10);

    // --- NEW: Test Summary ---
    #50;
    $display("\n===============================================================");
    if (error_count == 0)
      $display("  SIMULATION PASSED (%0d/%0d checks successful)", test_count, test_count);
    else
      $display("  SIMULATION FAILED (%0d errors out of %0d checks)", error_count, test_count);
    $display("===============================================================");
    
    $finish;
  end

endmodule