//==============================================================================
// Module: accel_ip_top
// Purpose: Top-level AI/ML Accelerator IP integration
// Instantiates: AXI Slave, Array Controller, PE Array, SRAM, and routing logic
// Interfaces: AXI4-Lite slave port, global clk/rst_n
// Architecture: 4×4 Processing Element systolic array for neural net inference
//==============================================================================

module accel_ip_top (
  input                clk,
  input                rst_n,
  
  // AXI4-Lite Write Address Channel
  input        [15:0]  axi_awaddr,
  input                axi_awvalid,
  output               axi_awready,
  
  // AXI4-Lite Write Data Channel
  input        [31:0]  axi_wdata,
  input                axi_wvalid,
  output               axi_wready,
  
  // AXI4-Lite Write Response Channel
  output               axi_bvalid,
  output       [1:0]   axi_bresp,
  input                axi_bready,
  
  // AXI4-Lite Read Address Channel
  input        [15:0]  axi_araddr,
  input                axi_arvalid,
  output               axi_arready,
  
  // AXI4-Lite Read Data Channel
  output       [31:0]  axi_rdata,
  output               axi_rvalid,
  output       [1:0]   axi_rresp,
  input                axi_rready
);

  //============================================================================
  // INTERNAL SIGNAL DECLARATIONS
  //============================================================================
  
  // Control signals from AXI Slave to Array Controller
  wire [7:0]   ctrl_cmd_w;
  wire [15:0]  base_addr_w;
  wire [1:0]   matrix_size_w;
  wire [1:0]   quantization_mode_w;
  wire         ctrl_write_valid_w;

  // Status signals from Array Controller to AXI Slave
  wire         status_done_w;
  wire         status_busy_w;
  wire         status_error_w;
  wire         status_overflow_w;
  wire [31:0]  cycle_count_w;
  wire [31:0]  error_code_w;

  // PE Array Control signals from Array Controller
  wire [3:0]   pe_en_w;
  wire         pe_clear_acc_w;
  wire [1:0]   pe_mode_w;

  // PE Array Output signals
  wire         pe_result_valid_w;
  wire [255:0] pe_result_w;         // Legacy full-array bus (kept for port matching)
  wire [3:0]   pe_overflow_w;
  
  // SRAM Control signals from Array Controller
  wire         sram_req_w;
  wire         sram_we_w;
  wire [9:0]   sram_addr_w;
  wire [63:0]  sram_wdata_w;

  // SRAM Output signals
  wire [63:0]  sram_rdata_w;
  wire         sram_ready_w;
  wire         sram_valid_w;

  // PE Array activation and weight inputs (from SRAM)
  wire [31:0] activation_in_w;
  wire [31:0] weight_in_w;

  // PE Array outputs (Streamed 1 column / 4 results per cycle)
  wire [63:0] pe_result_row_w;

  //============================================================================
  // MODULE INSTANTIATION BLOCK
  //============================================================================
  
  //--------------------------------------------------------------------------
  // 1. AXI4-Lite Slave Interface
  //--------------------------------------------------------------------------
  axi4_lite_slave i_axi_slave (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // AXI Channels
    .axi_awaddr             (axi_awaddr),
    .axi_awvalid            (axi_awvalid),
    .axi_awready            (axi_awready),
    .axi_wdata              (axi_wdata),
    .axi_wvalid             (axi_wvalid),
    .axi_wready             (axi_wready),
    .axi_bvalid             (axi_bvalid),
    .axi_bresp              (axi_bresp),
    .axi_bready             (axi_bready),
    .axi_araddr             (axi_araddr),
    .axi_arvalid            (axi_arvalid),
    .axi_arready            (axi_arready),
    .axi_rdata              (axi_rdata),
    .axi_rvalid             (axi_rvalid),
    .axi_rresp              (axi_rresp),
    .axi_rready             (axi_rready),
    
    // Control Register Outputs
    .ctrl_cmd               (ctrl_cmd_w),
    .base_addr              (base_addr_w),
    .matrix_size            (matrix_size_w),
    .quantization_mode      (quantization_mode_w),
    .ctrl_write_valid       (ctrl_write_valid_w),
   
    // Status Inputs
    .status_done            (status_done_w),
    .status_busy            (status_busy_w),
    .status_error           (status_error_w),
    .status_overflow        (status_overflow_w),
    .cycle_count            (cycle_count_w),
    .error_code             (error_code_w)
  );
  
  //--------------------------------------------------------------------------
  // 2. Array Controller FSM
  //--------------------------------------------------------------------------
  array_controller_fsm i_array_controller (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // Command Interface
    .cmd                    (ctrl_cmd_w),
    .base_addr              (base_addr_w),
    .matrix_size            (matrix_size_w),
    .quantization_mode      (quantization_mode_w),
    
    // PE Array Interface
    .pe_en                  (pe_en_w),
    .pe_clear_acc           (pe_clear_acc_w),
    .pe_mode                (pe_mode_w),
    .pe_result_valid        (pe_result_valid_w),
    
    // Result routing (Mapped newly streamed 16-bit chunks)
    .pe_result              (pe_result_w),             // Tied to 0 below
    .pe_overflow            (pe_overflow_w),
    .pe_result_0            (pe_result_row_w[15:0]),   // Streamed Row 0
    .pe_result_1            (pe_result_row_w[31:16]),  // Streamed Row 1
    .pe_result_2            (pe_result_row_w[47:32]),  // Streamed Row 2
    .pe_result_3            (pe_result_row_w[63:48]),  // Streamed Row 3
    
    // SRAM Interface
    .sram_req               (sram_req_w),
    .sram_we                (sram_we_w),
    .sram_addr              (sram_addr_w),
    .sram_wdata             (sram_wdata_w),
    .sram_rdata             (sram_rdata_w),
    .sram_ready             (sram_ready_w),
    .sram_valid             (sram_valid_w),
    
    // Status Interface
    .status_done            (status_done_w),
    .status_busy            (status_busy_w),
    .status_error           (status_error_w),
    .status_overflow        (status_overflow_w),
    .cycle_count            (cycle_count_w),
    .error_code             (error_code_w)
  );
  
  //--------------------------------------------------------------------------
  // 3. SRAM Controller
  //--------------------------------------------------------------------------
  sram_controller i_sram (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .sram_req               (sram_req_w),
    .sram_we                (sram_we_w),
    .sram_addr              (sram_addr_w),
    .sram_wdata             (sram_wdata_w),
    .sram_rdata             (sram_rdata_w),
    .sram_ready             (sram_ready_w),
    .sram_valid             (sram_valid_w)
  );
  
  //--------------------------------------------------------------------------
  // 4. PE Array (4×4 Systolic Grid)
  //--------------------------------------------------------------------------
  pe_array_4x4 i_pe_array (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .activation_in          (activation_in_w),
    .weight_in              (weight_in_w),
    .pe_en                  (pe_en_w),
    .clear_acc              (pe_clear_acc_w),
    .pe_mode                (pe_mode_w),
    .result_out             (pe_result_row_w),
    .result_valid           (pe_result_valid_w),
    .overflow_flags         (pe_overflow_w)
  );

  //============================================================================
  // INTERNAL SIGNAL ROUTING & LOGIC
  //============================================================================
  
  //--------------------------------------------------------------------------
  // SRAM Data Routing: Unpack 64-bit SRAM data into activation/weight buses
  //--------------------------------------------------------------------------
  assign weight_in_w[7:0]  = sram_rdata_w[7:0];    // Weight row 0
  assign weight_in_w[15:8]  = sram_rdata_w[15:8];   // Weight row 1
  assign weight_in_w[23:16]  = sram_rdata_w[23:16];  // Weight row 2
  assign weight_in_w[31:24]  = sram_rdata_w[31:24];  // Weight row 3
  
  assign activation_in_w[7:0] = sram_rdata_w[7:0];   // Activation row 0
  assign activation_in_w[15:8] = sram_rdata_w[15:8];  // Activation row 1
  assign activation_in_w[23:16] = sram_rdata_w[23:16]; // Activation row 2
  assign activation_in_w[31:24] = sram_rdata_w[31:24]; // Activation row 3
  
  //--------------------------------------------------------------------------
  // Legacy Port Tie-Off
  //--------------------------------------------------------------------------
  // Safely zero out the 256-bit bus since the array now streams data sequentially
  assign pe_result_w = 256'h0;

endmodule